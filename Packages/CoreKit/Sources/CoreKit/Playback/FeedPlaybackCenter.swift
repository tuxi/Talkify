//
//  FeedPlaybackCenter.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import Foundation
import CoreGraphics

@MainActor
public final class FeedPlaybackCenter {
    public enum LifecycleState: Equatable {
        case active
        case suspended
        case shutdown
    }
    
    public let networkPolicy: PreviewNetworkPolicy
    public let assetRepository: PreviewAssetRepository
    public let playerPool: PlayerPool
    public let playbackController: PreviewPlaybackController
    
    private var sections: [String: PlaybackSectionSnapshot] = [:]
    private var debounceTask: Task<Void, Never>?
    private var runtimeStates: [String: PlaybackRuntimeState] = [:]
    private var scrollSignal: PreviewScrollSignal = .idle
    private var resolveCount: Int = 0

    private let switchDebounceNanoseconds: UInt64
    private let scoringPolicy: PlaybackScoringPolicy
    private let budget: PlaybackBudget
    
    public private(set) var lifecycleState: LifecycleState = .active

    private var lastResolvedActiveIDs: Set<String> = []
    private var lastResolvedPreloadIDs: [String] = []

    public init(
        switchDebounceNanoseconds: UInt64 = 150_000_000,
        scoringPolicy: PlaybackScoringPolicy = .init(),
        budget: PlaybackBudget = .init(),
        assetRepository: PreviewAssetRepository? = nil
    ) {
        self.switchDebounceNanoseconds = switchDebounceNanoseconds
        self.scoringPolicy = scoringPolicy
        self.budget = budget

        self.networkPolicy = PreviewNetworkPolicy(
            allowAutoPlayOnCellular: true,
            allowPreloadOnCellular: false
        )
        
        let repository: PreviewAssetRepository
        if let assetRepository {
            repository = assetRepository
        } else {
            let fileCache: PreviewFileCache
            do {
                fileCache = try PreviewFileCache()
            } catch {
                fatalError("Failed to initialize PreviewFileCache: \(error.localizedDescription)")
            }
            repository = DefaultPreviewAssetRepository(fileCache: fileCache)
        }

        self.assetRepository = repository
        
        self.playerPool = PlayerPool(
            assetRepository: repository,
            maxCachedPlayers: 10,
        )

        self.playbackController = PreviewPlaybackController(
            playerPool: playerPool,
            assetRepository: repository,
            networkPolicy: networkPolicy
        )
    }

    public func register(playables: [PreviewPlayable]) {
        playbackController.register(playables: playables)
    }

    public func preheat(playables: [PreviewPlayable]) {
        playbackController.preheat(playables: playables)
    }

    public func updateScrollSignal(_ signal: PreviewScrollSignal) {
        scrollSignal = signal
    }

    public func updateSection(_ snapshot: PlaybackSectionSnapshot, forceCommit: Bool = false) {
        guard lifecycleState != .shutdown else { return }
        sections[snapshot.sectionID] = snapshot
        scheduleResolve(forceCommit: forceCommit)
    }

    public func removeSection(sectionID: String, ids: [String]) {
        sections.removeValue(forKey: sectionID)
        playbackController.pause(ids: ids)
        playbackController.unregister(ids: ids)

        for id in ids {
            runtimeStates.removeValue(forKey: id)
        }

        scheduleResolve(forceCommit: true)
    }

    public func pauseAll() {
        debounceTask?.cancel()
        debounceTask = nil
        playbackController.pauseAll()
    }

    public func suspend() {
        debounceTask?.cancel()
        debounceTask = nil
        lifecycleState = .suspended
        playbackController.suspendAll()
        PreviewPlaybackLogger.log("FeedPlaybackCenter suspend")
    }

    public func resume() {
        guard lifecycleState != .shutdown else { return }
        lifecycleState = .active
        playbackController.resume()
        PreviewPlaybackLogger.log("FeedPlaybackCenter resume")
        scheduleResolve(forceCommit: true)
    }

    public func shutdown() {
        debounceTask?.cancel()
        debounceTask = nil
        lifecycleState = .shutdown
        sections.removeAll()
        runtimeStates.removeAll()
        playbackController.shutdownAll()
        PreviewPlaybackLogger.log("FeedPlaybackCenter shutdown")
    }

    public func resumeNow() {
        resume()
    }

    public func debugDumpState() {
        PreviewPlaybackLogger.log(
            "FeedPlaybackCenter lifecycle=\(String(describing: lifecycleState)) sections=\(Array(sections.keys).sorted())"
        )
        let snapshot = playbackController.telemetrySnapshot()
        PreviewPlaybackLogger.logEvent(
            "telemetry_snapshot",
            fields: [
                "register_count": "\(snapshot.registerCount)",
                "winner_selection_count": "\(snapshot.winnerSelectionCount)",
                "cache_hit_winner_count": "\(snapshot.cacheHitWinnerCount)",
                "cache_miss_winner_count": "\(snapshot.cacheMissWinnerCount)",
                "first_frame_ready_count": "\(snapshot.firstFrameReadyCount)",
                "avg_activation_to_first_frame_ms": "\(Int(snapshot.averageActivationToFirstFrame * 1000))",
                "avg_register_to_first_frame_ms": "\(Int(snapshot.averageRegisterToFirstFrame * 1000))"
            ]
        )
        playbackController.debugDumpState()
        
        Task { @MainActor in
            await assetRepository.debugDumpState()
        }
    }

    private func scheduleResolve(forceCommit: Bool) {
        guard lifecycleState == .active else { return }

        debounceTask?.cancel()

        if forceCommit {
            resolveNow()
            return
        }

        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: switchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self.resolveNow()
        }
    }

    private func resolveNow() {
        guard lifecycleState == .active else { return }

        let candidates = buildGlobalCandidates()
        let winners = selectWinners(from: candidates)
        resolveCount += 1

        let activeIDs = Set(winners.map(\.id))
        let preloadIDs = buildPreloadIDs(from: winners)
        
        if activeIDs == lastResolvedActiveIDs && preloadIDs == lastResolvedPreloadIDs {
            PreviewPlaybackLogger.log("resolveNow skipped same winners/preload")
            return
        }

        lastResolvedActiveIDs = activeIDs
        lastResolvedPreloadIDs = preloadIDs
        
        playbackController.applyPlayingTargets(activeIDs)

        syncRuntimeStates(with: winners, activeIDs: activeIDs)

        playbackController.updatePreloadingTargets(preloadIDs)

        PreviewPlaybackLogger.log("resolveNow winners=\(winners.map(\.id)) preload=\(preloadIDs)")
        PreviewPlaybackLogger.logEvent(
            "resolve",
            fields: [
                "resolve_index": "\(resolveCount)",
                "candidate_count": "\(candidates.count)",
                "winner_count": "\(winners.count)",
                "preload_count": "\(preloadIDs.count)",
                "fast_scroll": "\(isFastScroll)",
                "velocity": format(scrollSignal.verticalVelocity),
                "winner_ids": winners.map(\.id).joined(separator: ",")
            ]
        )
    }

    private func buildGlobalCandidates() -> [GlobalPlaybackCandidate] {
        var all: [GlobalPlaybackCandidate] = []

        for (_, section) in sections where section.isAutoplayEnabled {
            all.append(contentsOf: buildCandidates(for: section))
        }

        return all.sorted(by: candidateSort)
    }

    private func buildCandidates(for section: PlaybackSectionSnapshot) -> [GlobalPlaybackCandidate] {
        let sectionTop = section.sectionFrame.minY
        let sectionPriorityBoost = max(0, 10_000 - sectionTop) / 10_000

        return section.visibleItems
            .filter { item in
                let isCurrentlyPlaying = playbackController.isPlaying(item.id)
                let threshold = isCurrentlyPlaying
                    ? scoringPolicy.minimumVisibleRatioToKeep
                    : scoringPolicy.minimumVisibleRatioToEnter

                return item.isVisible && item.visibleRatio >= threshold
            }
            .map { item in
                let visibilityScore = item.visibleRatio * 1000
                let topSectionScore = sectionPriorityBoost * scoringPolicy.sectionTopPriorityWeight
                let sectionPriorityScore = section.sectionPriority * 100

                let layoutScore: CGFloat
                switch section.sectionKind {
                case .carousel:
                    let centerScore = max(0, 1000 - item.horizontalDistanceToViewportCenter)
                    layoutScore = centerScore

                case .grid:
                    // grid 更应该偏向“上方优先”，而不是整屏中心优先
                    let rowOffset = max(0, item.frame.minY - section.sectionFrame.minY)
                    let topBias = max(0, 1000 - rowOffset * 1.8)
                    let verticalCenterScore = max(0, 720 - item.verticalDistanceToViewportCenter * 0.9)
                    let horizontalCenterScore = max(0, 220 - item.horizontalDistanceToViewportCenter * 0.18)

                    layoutScore = topBias + verticalCenterScore + horizontalCenterScore
                }

                var finalScore = topSectionScore + sectionPriorityScore + visibilityScore + layoutScore
                
                if playbackController.isPlaying(item.id) {
                    finalScore += scoringPolicy.currentlyPlayingBonus
                }

                if playbackController.isFirstFrameReady(item.id) {
                    finalScore += scoringPolicy.firstFrameReadyBonus
                }

                return GlobalPlaybackCandidate(
                    id: item.id,
                    sectionID: section.sectionID,
                    score: finalScore,
                    visibleRatio: item.visibleRatio,
                    horizontalDistanceToViewportCenter: item.horizontalDistanceToViewportCenter,
                    verticalDistanceToViewportCenter: item.verticalDistanceToViewportCenter,
                    frame: item.frame
                )
            }
            .sorted(by: candidateSort)
    }

    private func selectWinners(from sortedCandidates: [GlobalPlaybackCandidate]) -> [GlobalPlaybackCandidate] {
        guard !sortedCandidates.isEmpty else { return [] }

        let now = Date()
        let resolvedBudget = resolvedPlaybackBudget()
        let currentActiveIDs = playbackController.activePlayingIDs
        let currentlyPlayingCandidates = sortedCandidates.filter { currentActiveIDs.contains($0.id) }

        var winners: [GlobalPlaybackCandidate] = []
        var roleCounts: [PlaybackSectionRole: Int] = [:]

        for candidate in currentlyPlayingCandidates {
            guard winners.count < resolvedBudget.maxConcurrentPlayingCount else { break }

            if shouldKeepPlaying(candidate, now: now),
               canAdd(candidate, to: winners, roleCounts: roleCounts, budget: resolvedBudget) {
                winners.append(candidate)
                let role = role(for: candidate)
                roleCounts[role, default: 0] += 1
            }
        }

        for candidate in sortedCandidates {
            guard winners.count < resolvedBudget.maxConcurrentPlayingCount else { break }
            if winners.contains(where: { $0.id == candidate.id }) { continue }
            if !canAdd(candidate, to: winners, roleCounts: roleCounts, budget: resolvedBudget) { continue }

            if let existing = winners.first,
               existing.id != candidate.id,
               existing.score > candidate.score - scoringPolicy.switchingScoreDeltaThreshold {
                continue
            }

            winners.append(candidate)
            let role = role(for: candidate)
            roleCounts[role, default: 0] += 1
        }

        return winners
    }

    private func shouldKeepPlaying(_ candidate: GlobalPlaybackCandidate, now: Date) -> Bool {
        guard let runtime = runtimeStates[candidate.id], runtime.isPlaying else {
            return false
        }

        guard let startedAt = runtime.startedAt else {
            return true
        }

        let elapsed = now.timeIntervalSince(startedAt)

        if candidate.visibleRatio < scoringPolicy.minimumVisibleRatioToKeep {
            return false
        }

        if elapsed < scoringPolicy.minimumPlayDuration {
            return true
        }

        return true
    }

    private func syncRuntimeStates(with winners: [GlobalPlaybackCandidate], activeIDs: Set<String>) {
        let now = Date()

        for candidate in winners {
            var state = runtimeStates[candidate.id] ?? PlaybackRuntimeState(id: candidate.id)

            if !state.isPlaying {
                state.startedAt = now
            }

            state.isPlaying = true
            state.lastScore = candidate.score
            state.lastVisibleRatio = candidate.visibleRatio
            runtimeStates[candidate.id] = state
        }

        for id in runtimeStates.keys {
            if !activeIDs.contains(id) {
                var state = runtimeStates[id] ?? PlaybackRuntimeState(id: id)
                state.isPlaying = false
                runtimeStates[id] = state
            }
        }
    }

    private func candidateSort(_ lhs: GlobalPlaybackCandidate, _ rhs: GlobalPlaybackCandidate) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.visibleRatio != rhs.visibleRatio {
            return lhs.visibleRatio > rhs.visibleRatio
        }
        if lhs.verticalDistanceToViewportCenter != rhs.verticalDistanceToViewportCenter {
            return lhs.verticalDistanceToViewportCenter < rhs.verticalDistanceToViewportCenter
        }
        return lhs.horizontalDistanceToViewportCenter < rhs.horizontalDistanceToViewportCenter
    }

    private func buildPreloadIDs(from winners: [GlobalPlaybackCandidate]) -> [String] {
        var ids: [String] = []

        for winner in winners {
            guard let section = sections[winner.sectionID],
                  let currentIndex = preferredIDs(in: section).firstIndex(of: winner.id) else {
                continue
            }

            let ordered = preferredIDs(in: section)
            let forwardCount = scrollSignal.direction == .up ? 1 : 2
            let backwardCount = scrollSignal.direction == .up ? 2 : 1
            let next = ordered.dropFirst(currentIndex + 1).prefix(forwardCount)
            let prevStart = max(0, currentIndex - backwardCount)
            let prev = currentIndex > 0 ? Array(ordered[prevStart..<currentIndex].reversed()) : []

            ids.append(contentsOf: next)
            ids.append(contentsOf: prev)
        }

        return (NSOrderedSet(array: ids).array as? [String]) ?? []
    }

    private func preferredIDs(in section: PlaybackSectionSnapshot) -> [String] {
        section.preferredPreloadIDs.isEmpty ? section.orderedIDs : section.preferredPreloadIDs
    }

    private func resolvedPlaybackBudget() -> ResolvedPlaybackBudget {
        return ResolvedPlaybackBudget(
            maxConcurrentPlayingCount: isFastScroll
                ? budget.fastScrollMaxConcurrentPlayingCount
                : budget.steadyStateMaxConcurrentPlayingCount,
            featuredReservedSlots: budget.featuredSectionReservedSlots,
            gridReservedSlots: budget.gridSectionReservedSlots
        )
    }

    private func role(for candidate: GlobalPlaybackCandidate) -> PlaybackSectionRole {
        sections[candidate.sectionID]?.sectionRole ?? .grid
    }

    private func canAdd(
        _ candidate: GlobalPlaybackCandidate,
        to winners: [GlobalPlaybackCandidate],
        roleCounts: [PlaybackSectionRole: Int],
        budget: ResolvedPlaybackBudget
    ) -> Bool {
        guard winners.count < budget.maxConcurrentPlayingCount else { return false }

        let candidateRole = role(for: candidate)
        let roleLimit = min(limit(for: candidateRole, budget: budget), budget.maxConcurrentPlayingCount)
        let currentRoleCount = roleCounts[candidateRole, default: 0]

        if currentRoleCount < roleLimit {
            return true
        }

        let remainingSlots = budget.maxConcurrentPlayingCount - winners.count
        let unmetSlots = PlaybackSectionRole.allCases
            .filter { $0 != candidateRole }
            .reduce(0) { partialResult, role in
                let limit = min(self.limit(for: role, budget: budget), budget.maxConcurrentPlayingCount)
                let count = roleCounts[role, default: 0]
                return partialResult + max(0, limit - count)
            }

        return remainingSlots > unmetSlots
    }

    private func limit(for role: PlaybackSectionRole, budget: ResolvedPlaybackBudget) -> Int {
        switch role {
        case .featured:
            return budget.featuredReservedSlots
        case .grid:
            return budget.gridReservedSlots
        }
    }

    private var isFastScroll: Bool {
        scrollSignal.isDragging &&
            abs(scrollSignal.verticalVelocity) >= budget.fastScrollVelocityThreshold
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}

private struct ResolvedPlaybackBudget {
    let maxConcurrentPlayingCount: Int
    let featuredReservedSlots: Int
    let gridReservedSlots: Int
}

private extension PlaybackSectionRole {
    static let allCases: [PlaybackSectionRole] = [.featured, .grid]
}

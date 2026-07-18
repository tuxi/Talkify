//
//  PreviewPlaybackController.swift
//

import AVFoundation
import Foundation

@MainActor
@Observable
public final class PreviewPlaybackController {
    private let playerPool: PlayerPool
    private let assetRepository: PreviewAssetRepository
    private let networkPolicy: PreviewNetworkPolicy

    public private(set) var activePlayingIDs: Set<String> = []
    public private(set) var firstFrameReadyIDs: Set<String> = []
    public private(set) var preloadingIDs: Set<String> = []

    private var playablesByID: [String: PreviewPlayable] = [:]
    private var registeredAtByID: [String: Date] = [:]
    private var activatedAtByID: [String: Date] = [:]
    private var isSuspended = false
    public private(set) var playerMaterializationVersion: Int = 0
    private let telemetry = PreviewPlaybackTelemetry()

    public init(
        playerPool: PlayerPool,
        assetRepository: PreviewAssetRepository,
        networkPolicy: PreviewNetworkPolicy
    ) {
        self.playerPool = playerPool
        self.assetRepository = assetRepository
        self.networkPolicy = networkPolicy
    }

    public func register(playables: [PreviewPlayable]) {
        let now = Date()
        for playable in playables {
            playablesByID[playable.id] = playable
            registeredAtByID[playable.id] = registeredAtByID[playable.id] ?? now
        }
        telemetry.recordRegister(count: playables.count)
        PreviewPlaybackLogger.log("register playables count=\(playables.count)")
        PreviewPlaybackLogger.logEvent(
            "register_playables",
            fields: [
                "count": "\(playables.count)",
                "ids": playables.map(\.id).joined(separator: ",")
            ]
        )
    }

    public func unregister(ids: [String]) {
        let resourceIDs = ids.compactMap { playablesByID[$0]?.resourceID }

        for id in ids {
            playablesByID.removeValue(forKey: id)
            firstFrameReadyIDs.remove(id)
            activePlayingIDs.remove(id)
            preloadingIDs.remove(id)
            registeredAtByID.removeValue(forKey: id)
            activatedAtByID.removeValue(forKey: id)
        }

        assetRepository.cancelPreload(resourceIDs: resourceIDs)
        playerPool.removePlayers(ids: ids)

        playerMaterializationVersion &+= 1
        PreviewPlaybackLogger.log("unregister ids=\(ids)")
    }

    public func applyPlayingTargets(_ ids: Set<String>) {
        let targetIDs: Set<String>
        if isSuspended || !networkPolicy.canAutoPlay {
            targetIDs = []
        } else {
            targetIDs = ids
        }

        let removed = activePlayingIDs.subtracting(targetIDs)
        let added = targetIDs.subtracting(activePlayingIDs)
        let kept = activePlayingIDs.intersection(targetIDs)

        PreviewPlaybackLogger.log(
            "applyPlayingTargets old=\(Array(activePlayingIDs).sorted()) new=\(Array(targetIDs).sorted()) added=\(Array(added).sorted()) removed=\(Array(removed).sorted()) kept=\(Array(kept).sorted())"
        )

        for id in removed {
            guard let player = playerPool.playerIfLoaded(for: id) else { continue }
            player.pause()
        }

        for id in kept {
            guard let player = playerPool.playerIfLoaded(for: id) else { continue }
            if player.timeControlStatus != .playing {
                player.play()
            }
        }

        for id in added {
            guard let playable = playablesByID[id] else { continue }
            let isCacheHit = assetRepository.isCached(resourceID: playable.resourceID)
            telemetry.recordWinnerSelection(isCacheHit: isCacheHit)
            activatedAtByID[id] = Date()
            PreviewPlaybackLogger.logEvent(
                "winner_selected",
                fields: [
                    "id": id,
                    "resource_id": playable.resourceID,
                    "cache_hit": "\(isCacheHit)"
                ]
            )
            Task { @MainActor in
                let player = await playerPool.ensurePlayer(for: playable)
                self.markPlayerMaterialized(for: id)
                await player.seek(to: .zero)
                player.play()
            }
            if networkPolicy.canPreload {
                Task { @MainActor in
                    await assetRepository.cacheCurrentPlaybackIfNeeded(playable)
                }
            }
        }
        
        activePlayingIDs = targetIDs
        playerPool.markActivePlayingIDs(targetIDs)
    }

    public func updatePreloadingTargets(_ ids: [String]) {
        let oldPreloadIDs = preloadingIDs
        let newPreloadIDs: Set<String>

        if isSuspended || !networkPolicy.canPreload {
            newPreloadIDs = []
        } else {
            newPreloadIDs = Set(ids)
        }

        let removed = oldPreloadIDs.subtracting(newPreloadIDs)
        let kept = oldPreloadIDs.intersection(newPreloadIDs)
        let added = newPreloadIDs.subtracting(oldPreloadIDs)

        let removedResourceIDs = removed.compactMap { playablesByID[$0]?.resourceID }
        assetRepository.cancelPreload(resourceIDs: removedResourceIDs)

        let playablesToPreload = added.compactMap { playablesByID[$0] }
        preloadingIDs = newPreloadIDs

        PreviewPlaybackLogger.log(
            "updatePreloadingTargets ids=\(Array(newPreloadIDs).sorted()) added=\(Array(added).sorted()) kept=\(Array(kept).sorted()) removed=\(Array(removed).sorted())"
        )
        PreviewPlaybackLogger.logEvent(
            "preload_targets_updated",
            fields: [
                "count": "\(newPreloadIDs.count)",
                "added": "\(added.count)",
                "removed": "\(removed.count)"
            ]
        )

        guard !playablesToPreload.isEmpty else { return }

        Task { @MainActor in
            await assetRepository.preload(playablesToPreload)
        }
    }

    public func preheat(playables: [PreviewPlayable]) {
        guard !playables.isEmpty, networkPolicy.canPreload else { return }
        PreviewPlaybackLogger.logEvent(
            "preheat_requested",
            fields: [
                "count": "\(playables.count)",
                "resource_ids": playables.map(\.resourceID).joined(separator: ",")
            ]
        )
        Task { @MainActor in
            await assetRepository.preheat(playables)
        }
    }

    public func player(for id: String) -> AVPlayer? {
        playerPool.playerIfLoaded(for: id)
    }

    public func isPlaying(_ id: String) -> Bool {
        activePlayingIDs.contains(id)
    }

    public func preload(_ ids: [String]) {
        updatePreloadingTargets(ids)
    }
    
    public func markFirstFrameReady(for id: String) {
        guard playablesByID[id] != nil else {
            PreviewPlaybackLogger.log("ignore late firstFrameReady id=\(id)")
            return
        }
        guard !firstFrameReadyIDs.contains(id) else { return }
        firstFrameReadyIDs.insert(id)
        let now = Date()
        let activationLatency = activatedAtByID[id].map { now.timeIntervalSince($0) }
        let registerLatency = registeredAtByID[id].map { now.timeIntervalSince($0) }
        telemetry.recordFirstFrame(
            activationToFirstFrame: activationLatency,
            registerToFirstFrame: registerLatency
        )
        PreviewPlaybackLogger.log("firstFrameReady id=\(id)")
        PreviewPlaybackLogger.logEvent(
            "first_frame_ready",
            fields: [
                "id": id,
                "activation_to_first_frame_ms": "\(Int((activationLatency ?? 0) * 1000))",
                "register_to_first_frame_ms": "\(Int((registerLatency ?? 0) * 1000))"
            ]
        )
    }
    
    public func isFirstFrameReady(_ id: String) -> Bool {
        firstFrameReadyIDs.contains(id)
    }

    public func pause(ids: [String]) {
        for id in ids {
            playerPool.playerIfLoaded(for: id)?.pause()
            activePlayingIDs.remove(id)
            preloadingIDs.remove(id)
        }
        playerPool.markActivePlayingIDs(activePlayingIDs)
        PreviewPlaybackLogger.log("pause ids=\(ids)")
    }

    public func pauseAll() {
        for id in activePlayingIDs {
            playerPool.playerIfLoaded(for: id)?.pause()
        }
        activePlayingIDs.removeAll()
        playerPool.markActivePlayingIDs([])
        PreviewPlaybackLogger.log("pauseAll")
    }

    public func suspendAll() {
        isSuspended = true
        activePlayingIDs.removeAll()

        let resourceIDs = preloadingIDs.compactMap { playablesByID[$0]?.resourceID }
        preloadingIDs.removeAll()
        assetRepository.cancelPreload(resourceIDs: resourceIDs)

        playerPool.suspendAll()
        PreviewPlaybackLogger.log("suspendAll controller")
    }

    public func resume() {
        isSuspended = false
        PreviewPlaybackLogger.log("resume controller")
    }

    public func shutdownAll() {
        isSuspended = true
        activePlayingIDs.removeAll()
        preloadingIDs.removeAll()
        firstFrameReadyIDs.removeAll()
        playablesByID.removeAll()

        assetRepository.cancelAllPreloads()
        playerPool.cleanupAll()

        playerMaterializationVersion &+= 1
        PreviewPlaybackLogger.log("shutdownAll controller")
    }

    public func debugDumpState() {
        PreviewPlaybackLogger.log(
            "controller state active=\(Array(activePlayingIDs).sorted()) preload=\(Array(preloadingIDs).sorted()) firstFrameReady=\(Array(firstFrameReadyIDs).sorted()) suspended=\(isSuspended)"
        )
        playerPool.debugDumpState()
    }

    public func telemetrySnapshot() -> PreviewPlaybackTelemetry.Snapshot {
        telemetry.snapshot()
    }
    
    private func markPlayerMaterialized(for id: String) {
        guard playablesByID[id] != nil else { return }
        playerMaterializationVersion &+= 1
        PreviewPlaybackLogger.log("playerMaterialized id=\(id) version=\(playerMaterializationVersion)")
    }
}

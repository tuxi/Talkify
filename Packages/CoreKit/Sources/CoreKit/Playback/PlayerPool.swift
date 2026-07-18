//
//  PlayerPool.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import AVFoundation
import Foundation

@MainActor
public final class PlayerPool {
    public final class Slot {
        public let playable: PreviewPlayable
        public let player: AVPlayer

        public var lastAccessDate: Date
        public var isActivePlaying: Bool = false
        public var endObserver: NSObjectProtocol?
        public var resolvedURL: URL?

        init(playable: PreviewPlayable, player: AVPlayer) {
            self.playable = playable
            self.player = player
            self.lastAccessDate = Date()
        }

        deinit {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
        }
    }

    private var slots: [String: Slot] = [:]
    private let maxCachedPlayers: Int
    private let assetRepository: PreviewAssetRepository
    private var creatingTasks: [String: Task<AVPlayer, Never>] = [:]

    public init(
        assetRepository: PreviewAssetRepository,
        maxCachedPlayers: Int = 6
    ) {
        self.assetRepository = assetRepository
        self.maxCachedPlayers = maxCachedPlayers
    }

    public func ensurePlayer(for playable: PreviewPlayable) async -> AVPlayer {
        if let slot = slots[playable.id] {
            slot.lastAccessDate = Date()
            PreviewPlaybackLogger.log("reuse player slot id=\(playable.id)")
            return slot.player
        }

        if let existingTask = creatingTasks[playable.id] {
            PreviewPlaybackLogger.log("await existing creating task id=\(playable.id)")
            return await existingTask.value
        }

        let task = Task<AVPlayer, Never> { @MainActor [weak self] in
            guard let self else { return AVPlayer() }

            let created = await self.makeSlot(for: playable)
            self.slots[playable.id] = created
            self.creatingTasks.removeValue(forKey: playable.id)

            PreviewPlaybackLogger.log("create player slot id=\(playable.id) resourceID=\(playable.resourceID)")
            self.trimIfNeeded(activeIDs: self.currentActiveIDs())
            return created.player
        }

        creatingTasks[playable.id] = task
        return await task.value
    }

    public func playerIfLoaded(for id: String) -> AVPlayer? {
        guard let slot = slots[id] else { return nil }
        slot.lastAccessDate = Date()
        return slot.player
    }

    public func markActivePlayingIDs(_ ids: Set<String>) {
        for (slotID, slot) in slots {
            slot.isActivePlaying = ids.contains(slotID)
        }
    }

    public func pauseAll(except id: String? = nil) {
        for (slotID, slot) in slots where slotID != id {
            slot.player.pause()
            slot.isActivePlaying = false
        }
        PreviewPlaybackLogger.log("pauseAll except=\(id ?? "nil")")
    }

    public func suspendAll() {
        for (_, slot) in slots {
            slot.player.pause()
            slot.isActivePlaying = false
        }
        PreviewPlaybackLogger.log("suspendAll slots=\(slots.count)")
    }

    public func cleanupAll() {
        PreviewPlaybackLogger.log("cleanupAll slots=\(slots.count)")
        for (_, slot) in slots {
            slot.player.pause()
           let task = creatingTasks[slot.playable.id]
            task?.cancel()
            slot.player.replaceCurrentItem(with: nil)
            if let observer = slot.endObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        slots.removeAll()
    }

    public func removePlayers(ids: [String]) {
        for id in ids {
            remove(slotID: id)
        }
    }

    public func debugDumpState() {
        let ids = slots.keys.sorted()
        PreviewPlaybackLogger.log("PlayerPool slots=\(ids.count) ids=\(ids)")
    }

    private func makeSlot(for playable: PreviewPlayable) async -> Slot {
        let resolvedURL = await assetRepository.resolvedURL(for: playable)

        let item = AVPlayerItem(url: resolvedURL)
        item.preferredForwardBufferDuration = 2.5

        let player = AVPlayer(playerItem: item)
        player.isMuted = playable.muted
        player.actionAtItemEnd = .pause

        let slot = Slot(playable: playable, player: player)
        slot.resolvedURL = resolvedURL

        if playable.shouldLoop {
            slot.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                guard let player else { return }
                player.seek(to: .zero)
                player.play()
            }
        }

        PreviewPlaybackLogger.log("makeSlot resolvedURL=\(resolvedURL.absoluteString) playableID=\(playable.id)")
        return slot
    }

    private func trimIfNeeded(activeIDs: Set<String>) {
        guard slots.count > maxCachedPlayers else { return }

        let removable = slots.values.sorted { lhs, rhs in
            evictionRank(of: lhs, activeIDs: activeIDs) < evictionRank(of: rhs, activeIDs: activeIDs)
        }

        let removeCount = slots.count - maxCachedPlayers
        for slot in removable.prefix(removeCount) {
            remove(slotID: slot.playable.id)
        }
    }

    private func evictionRank(of slot: Slot, activeIDs: Set<String>) -> Int {
        if activeIDs.contains(slot.playable.id) || slot.isActivePlaying {
            return 10_000_000
        }
        return Int(slot.lastAccessDate.timeIntervalSince1970)
    }

    private func currentActiveIDs() -> Set<String> {
        Set(
            slots.compactMap { key, slot in
                slot.isActivePlaying ? key : nil
            }
        )
    }

    private func remove(slotID: String) {
        guard let slot = slots.removeValue(forKey: slotID) else { return }
        PreviewPlaybackLogger.log("remove slot id=\(slotID)")
        slot.player.pause()
        slot.player.replaceCurrentItem(with: nil)
        let task = creatingTasks[slot.playable.id]
        task?.cancel()
        if let observer = slot.endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

//
//  PreviewPlaybackSectionAdapter.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/11.
//

import Foundation
import CoreGraphics
import AVFoundation

@MainActor
public final class PreviewPlaybackSectionAdapter<Item>: ObservableObject {
    public let sectionID: String
    private let playbackCenter: FeedPlaybackCenter
    private let previewIDBuilder: (Item) -> String
    private let playableBuilder: (Item) -> PreviewPlayable?
    private let sectionKind: PlaybackSectionKind
    private let sectionRole: PlaybackSectionRole
    private let sectionPriority: CGFloat

    @Published public private(set) var visibilityMap: [String: VisibilitySnapshot] = [:]
    @Published public var sectionFrame: CGRect = .zero

    private var items: [Item] = []
    private var isAutoplayEnabled: Bool = true
    private var hasRegistered = false
    private var hasEmittedFirstFrame = false
    private var hasEmittedFirstVisibility = false
    private var lastCommittedSectionFrame: CGRect = .zero
    private var lastCommittedVisibleIDs: [String: CGFloat] = [:]

    public init(
        sectionID: String,
        playbackCenter: FeedPlaybackCenter,
        sectionKind: PlaybackSectionKind,
        sectionRole: PlaybackSectionRole = .grid,
        sectionPriority: CGFloat = 0,
        previewIDBuilder: @escaping (Item) -> String,
        playableBuilder: @escaping (Item) -> PreviewPlayable?
    ) {
        self.sectionID = sectionID
        self.playbackCenter = playbackCenter
        self.sectionKind = sectionKind
        self.sectionRole = sectionRole
        self.sectionPriority = sectionPriority
        self.previewIDBuilder = previewIDBuilder
        self.playableBuilder = playableBuilder
    }
    
    public func updateItems(_ items: [Item], isAutoplayEnabled: Bool) {
        self.items = items
        self.isAutoplayEnabled = isAutoplayEnabled
    }

    public func registerIfNeeded() {
        guard !hasRegistered else {
            pushSnapshot(forceCommit: true)
            return
        }

        let playables = items.compactMap(playableBuilder)
        guard !playables.isEmpty else {
            hasRegistered = true
            pushSnapshot(forceCommit: true)
            return
        }
        playbackCenter.register(playables: playables)
        hasRegistered = true
        pushSnapshot(forceCommit: true)
    }

    public func unregister() {
        let ids = orderedIDs
        playbackCenter.removeSection(sectionID: sectionID, ids: ids)
        visibilityMap.removeAll()
        hasRegistered = false
    }

    public func updateVisibility(_ snapshot: VisibilitySnapshot, forceCommit: Bool = false) {
        let oldRatio = visibilityMap[snapshot.id]?.visibleRatio ?? -1
        let oldVisible = visibilityMap[snapshot.id]?.isVisible ?? false

        let changedEnough =
            abs(oldRatio - snapshot.visibleRatio) > 0.05 ||
            oldVisible != snapshot.isVisible ||
            !hasEmittedFirstVisibility

        guard changedEnough || forceCommit else { return }

        visibilityMap[snapshot.id] = snapshot

        let shouldForce = forceCommit || !hasEmittedFirstVisibility
        hasEmittedFirstVisibility = true
        pushSnapshot(forceCommit: shouldForce)
    }
    
    public func updateSectionFrame(_ frame: CGRect, forceCommit: Bool = false) {
        let shouldUpdate =
            abs(frame.minY - lastCommittedSectionFrame.minY) > 2 ||
            abs(frame.height - lastCommittedSectionFrame.height) > 2 ||
            !hasEmittedFirstFrame

        guard shouldUpdate || forceCommit else { return }

        sectionFrame = frame
        lastCommittedSectionFrame = frame

        let shouldForce = forceCommit || !hasEmittedFirstFrame
        hasEmittedFirstFrame = true
        pushSnapshot(forceCommit: shouldForce)
    }
    
    public func pushSnapshot(forceCommit: Bool = false) {
        let snapshot = PlaybackSectionSnapshot(
            sectionID: sectionID,
            sectionFrame: sectionFrame,
            orderedIDs: orderedIDs,
            preferredPreloadIDs: preferredPreloadIDs,
            visibleItems: Array(visibilityMap.values),
            isAutoplayEnabled: isAutoplayEnabled,
            sectionKind: sectionKind,
            sectionRole: sectionRole,
            sectionPriority: sectionPriority
        )
        playbackCenter.updateSection(snapshot, forceCommit: forceCommit)
    }
    
    public func binding(for item: Item) -> PreviewPlaybackItemBinding {
        let id = previewIDBuilder(item)

        // 关键：读取这个可观察值，让 UI 在 player 创建后重算 body
        let renderVersion = playbackCenter.playbackController.playerMaterializationVersion

        return .init(
            id: id,
            player: playbackCenter.playbackController.player(for: id),
            isPlaying: playbackCenter.playbackController.isPlaying(id),
            isFirstFrameReady: playbackCenter.playbackController.isFirstFrameReady(id),
            renderVersion: renderVersion,
            onReadyForDisplay: { [weak playbackCenter] in
                playbackCenter?.playbackController.markFirstFrameReady(for: id)
            }
        )
    }

    public var orderedIDs: [String] {
        items.map(previewIDBuilder)
    }

    private var preferredPreloadIDs: [String] {
        let ids = orderedIDs
        guard !ids.isEmpty else { return [] }

        let anchorID = visibilityMap.values
            .filter(\.isVisible)
            .sorted { lhs, rhs in
                if lhs.visibleRatio != rhs.visibleRatio {
                    return lhs.visibleRatio > rhs.visibleRatio
                }
                return lhs.frame.minY < rhs.frame.minY
            }
            .first?
            .id

        guard let anchorID,
              let anchorIndex = ids.firstIndex(of: anchorID) else {
            return ids
        }

        return Array(ids[anchorIndex...]) + Array(ids[..<anchorIndex].reversed())
    }
}

public struct PreviewPlaybackItemBinding {
    public let id: String
    public let player: AVPlayer?
    public let isPlaying: Bool
    public let isFirstFrameReady: Bool
    public let renderVersion: Int
    public let onReadyForDisplay: () -> Void
}

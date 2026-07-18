//
//  PlaybackSectionSnapshot.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import Foundation
import CoreGraphics

public enum PlaybackSectionKind: Sendable {
    case carousel
    case grid
}

public enum PlaybackSectionRole: Sendable {
    case featured
    case grid
}

public struct PlaybackSectionSnapshot: Sendable {
    public let sectionID: String
    public let sectionFrame: CGRect
    public let orderedIDs: [String]
    public let preferredPreloadIDs: [String]
    public let visibleItems: [VisibilitySnapshot]
    public let isAutoplayEnabled: Bool
    public let sectionKind: PlaybackSectionKind
    public let sectionRole: PlaybackSectionRole
    public let sectionPriority: CGFloat

    public init(
        sectionID: String,
        sectionFrame: CGRect,
        orderedIDs: [String],
        preferredPreloadIDs: [String] = [],
        visibleItems: [VisibilitySnapshot],
        isAutoplayEnabled: Bool,
        sectionKind: PlaybackSectionKind,
        sectionRole: PlaybackSectionRole = .grid,
        sectionPriority: CGFloat = 0
    ) {
        self.sectionID = sectionID
        self.sectionFrame = sectionFrame
        self.orderedIDs = orderedIDs
        self.preferredPreloadIDs = preferredPreloadIDs
        self.visibleItems = visibleItems
        self.isAutoplayEnabled = isAutoplayEnabled
        self.sectionKind = sectionKind
        self.sectionRole = sectionRole
        self.sectionPriority = sectionPriority
    }
}

// 全局候选项
public struct GlobalPlaybackCandidate: Identifiable, Sendable {
    public let id: String
    public let sectionID: String
    public let score: CGFloat
    public let visibleRatio: CGFloat
    public let horizontalDistanceToViewportCenter: CGFloat
    public let verticalDistanceToViewportCenter: CGFloat
    public let frame: CGRect

    public init(
        id: String,
        sectionID: String,
        score: CGFloat,
        visibleRatio: CGFloat,
        horizontalDistanceToViewportCenter: CGFloat,
        verticalDistanceToViewportCenter: CGFloat,
        frame: CGRect
    ) {
        self.id = id
        self.sectionID = sectionID
        self.score = score
        self.visibleRatio = visibleRatio
        self.horizontalDistanceToViewportCenter = horizontalDistanceToViewportCenter
        self.verticalDistanceToViewportCenter = verticalDistanceToViewportCenter
        self.frame = frame
    }
}

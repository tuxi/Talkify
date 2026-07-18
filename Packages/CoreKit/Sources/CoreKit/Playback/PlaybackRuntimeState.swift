//
//  PlaybackRuntimeState.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/11.
//

import Foundation

public struct PlaybackRuntimeState: Sendable {
    public let id: String
    public var startedAt: Date?
    public var lastScore: CGFloat
    public var lastVisibleRatio: CGFloat
    public var isPlaying: Bool

    public init(
        id: String,
        startedAt: Date? = nil,
        lastScore: CGFloat = 0,
        lastVisibleRatio: CGFloat = 0,
        isPlaying: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.lastScore = lastScore
        self.lastVisibleRatio = lastVisibleRatio
        self.isPlaying = isPlaying
    }
}

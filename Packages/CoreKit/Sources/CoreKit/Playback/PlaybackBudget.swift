//
//  PlaybackBudget.swift
//  CoreKit
//
//  Created by Codex on 2026/4/23.
//

import CoreGraphics
import Foundation

public struct PlaybackBudget: Sendable {
    public let steadyStateMaxConcurrentPlayingCount: Int
    public let fastScrollMaxConcurrentPlayingCount: Int
    public let featuredSectionReservedSlots: Int
    public let gridSectionReservedSlots: Int
    public let fastScrollVelocityThreshold: CGFloat

    public init(
        steadyStateMaxConcurrentPlayingCount: Int = 2,
        fastScrollMaxConcurrentPlayingCount: Int = 1,
        featuredSectionReservedSlots: Int = 1,
        gridSectionReservedSlots: Int = 1,
        fastScrollVelocityThreshold: CGFloat = 1_000
    ) {
        self.steadyStateMaxConcurrentPlayingCount = steadyStateMaxConcurrentPlayingCount
        self.fastScrollMaxConcurrentPlayingCount = fastScrollMaxConcurrentPlayingCount
        self.featuredSectionReservedSlots = featuredSectionReservedSlots
        self.gridSectionReservedSlots = gridSectionReservedSlots
        self.fastScrollVelocityThreshold = fastScrollVelocityThreshold
    }
}

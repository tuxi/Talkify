//
//  PreviewPlaybackTelemetry.swift
//  CoreKit
//
//  Created by Codex on 2026/4/23.
//

import Foundation

@MainActor
public final class PreviewPlaybackTelemetry {
    public struct Snapshot: Sendable {
        public let registerCount: Int
        public let winnerSelectionCount: Int
        public let cacheHitWinnerCount: Int
        public let cacheMissWinnerCount: Int
        public let firstFrameReadyCount: Int
        public let averageActivationToFirstFrame: TimeInterval
        public let averageRegisterToFirstFrame: TimeInterval

        public init(
            registerCount: Int,
            winnerSelectionCount: Int,
            cacheHitWinnerCount: Int,
            cacheMissWinnerCount: Int,
            firstFrameReadyCount: Int,
            averageActivationToFirstFrame: TimeInterval,
            averageRegisterToFirstFrame: TimeInterval
        ) {
            self.registerCount = registerCount
            self.winnerSelectionCount = winnerSelectionCount
            self.cacheHitWinnerCount = cacheHitWinnerCount
            self.cacheMissWinnerCount = cacheMissWinnerCount
            self.firstFrameReadyCount = firstFrameReadyCount
            self.averageActivationToFirstFrame = averageActivationToFirstFrame
            self.averageRegisterToFirstFrame = averageRegisterToFirstFrame
        }
    }

    private var registerCount = 0
    private var winnerSelectionCount = 0
    private var cacheHitWinnerCount = 0
    private var cacheMissWinnerCount = 0
    private var firstFrameReadyCount = 0
    private var totalActivationToFirstFrame: TimeInterval = 0
    private var totalRegisterToFirstFrame: TimeInterval = 0

    public init() {}

    public func recordRegister(count: Int) {
        registerCount += count
    }

    public func recordWinnerSelection(isCacheHit: Bool) {
        winnerSelectionCount += 1
        if isCacheHit {
            cacheHitWinnerCount += 1
        } else {
            cacheMissWinnerCount += 1
        }
    }

    public func recordFirstFrame(
        activationToFirstFrame: TimeInterval?,
        registerToFirstFrame: TimeInterval?
    ) {
        firstFrameReadyCount += 1
        if let activationToFirstFrame {
            totalActivationToFirstFrame += activationToFirstFrame
        }
        if let registerToFirstFrame {
            totalRegisterToFirstFrame += registerToFirstFrame
        }
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            registerCount: registerCount,
            winnerSelectionCount: winnerSelectionCount,
            cacheHitWinnerCount: cacheHitWinnerCount,
            cacheMissWinnerCount: cacheMissWinnerCount,
            firstFrameReadyCount: firstFrameReadyCount,
            averageActivationToFirstFrame: firstFrameReadyCount > 0
                ? totalActivationToFirstFrame / Double(firstFrameReadyCount)
                : 0,
            averageRegisterToFirstFrame: firstFrameReadyCount > 0
                ? totalRegisterToFirstFrame / Double(firstFrameReadyCount)
                : 0
        )
    }
}

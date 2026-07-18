//
//  PlaybackScoringPolicy.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/11.
//


import CoreGraphics
import Foundation

public struct PlaybackScoringPolicy: Sendable {
    public let maxConcurrentPlayingCount: Int

    /// 新候选进入播放的最低可见比例
    public let minimumVisibleRatioToEnter: CGFloat

    /// 当前正在播放的 item 保持播放的最低可见比例
    public let minimumVisibleRatioToKeep: CGFloat

    /// 两个候选之间分数需要超过多少，才允许发生切换
    public let switchingScoreDeltaThreshold: CGFloat

    /// 播放中的 item 的额外加分，减少抖动
    public let currentlyPlayingBonus: CGFloat

    /// 首帧已准备好的 item 额外加分
    public let firstFrameReadyBonus: CGFloat

    /// 某个 item 一旦开始播放，至少保留多久，除非它几乎不可见
    public let minimumPlayDuration: TimeInterval

    /// section 越靠上时的加分上限
    public let sectionTopPriorityWeight: CGFloat

    public init(
        maxConcurrentPlayingCount: Int = 1,
        minimumVisibleRatioToEnter: CGFloat = 0.60,
        minimumVisibleRatioToKeep: CGFloat = 0.30,
        switchingScoreDeltaThreshold: CGFloat = 180,
        currentlyPlayingBonus: CGFloat = 420,
        firstFrameReadyBonus: CGFloat = 120,
        minimumPlayDuration: TimeInterval = 1.0,
        sectionTopPriorityWeight: CGFloat = 800
    ) {
        self.maxConcurrentPlayingCount = maxConcurrentPlayingCount
        self.minimumVisibleRatioToEnter = minimumVisibleRatioToEnter
        self.minimumVisibleRatioToKeep = minimumVisibleRatioToKeep
        self.switchingScoreDeltaThreshold = switchingScoreDeltaThreshold
        self.currentlyPlayingBonus = currentlyPlayingBonus
        self.firstFrameReadyBonus = firstFrameReadyBonus
        self.minimumPlayDuration = minimumPlayDuration
        self.sectionTopPriorityWeight = sectionTopPriorityWeight
    }
}

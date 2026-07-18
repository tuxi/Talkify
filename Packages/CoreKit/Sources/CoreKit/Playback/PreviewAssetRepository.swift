//
//  PreviewAssetRepository.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/11.
//

import Foundation

@MainActor
public protocol PreviewAssetRepository: AnyObject {
    func resolvedURL(for playable: PreviewPlayable) async -> URL
    func isCached(resourceID: String) -> Bool

    /// 只做资源预取，不创建 player
    func preload(_ playables: [PreviewPlayable]) async
    func preheat(_ playables: [PreviewPlayable]) async
    func cacheCurrentPlaybackIfNeeded(_ playable: PreviewPlayable) async

    /// 取消指定资源的预取
    func cancelPreload(resourceIDs: [String])

    /// 取消全部预取任务
    func cancelAllPreloads()

    func cacheState(for resourceID: String) -> PreviewAssetCacheState
    func removeAllCache() async
    func debugDumpState() async
}

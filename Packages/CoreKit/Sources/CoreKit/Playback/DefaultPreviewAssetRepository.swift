//
//  DefaultPreviewAssetRepository.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/11.
//


import Foundation

@MainActor
public final class DefaultPreviewAssetRepository: PreviewAssetRepository {
    private let fileCache: PreviewFileCache
    private let session: URLSession

    private var statesByResourceID: [String: PreviewAssetCacheState] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var protectedResourceIDs: Set<String> = []

    public init(
        fileCache: PreviewFileCache,
        session: URLSession = .shared
    ) {
        self.fileCache = fileCache
        self.session = session
    }

    public func resolvedURL(for playable: PreviewPlayable) async -> URL {
        if let local = await fileCache.cachedFileURLIfExists(
            for: playable.resourceID,
            remoteURL: playable.videoURL
        ) {
            statesByResourceID[playable.resourceID] = .cached(localFileURL: local)
            PreviewPlaybackLogger.log("asset hit local cache resourceID=\(playable.resourceID)")
            return local
        }

        if statesByResourceID[playable.resourceID] == nil {
            statesByResourceID[playable.resourceID] = .none
        }

        PreviewPlaybackLogger.log("asset miss local cache resourceID=\(playable.resourceID), fallback remote=\(playable.videoURL.absoluteString)")
        return playable.videoURL
    }

    public func isCached(resourceID: String) -> Bool {
        if case .cached = statesByResourceID[resourceID] {
            return true
        }
        return false
    }

    public func preload(_ playables: [PreviewPlayable]) async {
        for playable in playables {
            await startDownloadIfNeeded(for: playable, protectFromCancellation: false)
        }
    }

    public func preheat(_ playables: [PreviewPlayable]) async {
        for playable in playables {
            await startDownloadIfNeeded(for: playable, protectFromCancellation: true)
        }
    }

    public func cacheCurrentPlaybackIfNeeded(_ playable: PreviewPlayable) async {
        await startDownloadIfNeeded(for: playable, protectFromCancellation: true)
    }

    public func cancelPreload(resourceIDs: [String]) {
        for resourceID in resourceIDs {
            if protectedResourceIDs.contains(resourceID) {
                continue
            }
            guard let task = downloadTasks.removeValue(forKey: resourceID) else { continue }
            task.cancel()

            if case .cached = statesByResourceID[resourceID] {
                // 保留 cached 状态
            } else {
                statesByResourceID[resourceID] = .none
            }

            PreviewPlaybackLogger.log("cancel preload resourceID=\(resourceID)")
        }
    }

    public func cancelAllPreloads() {
        let ids = Array(downloadTasks.keys)
        for (resourceID, task) in downloadTasks {
            if protectedResourceIDs.contains(resourceID) {
                continue
            }
            task.cancel()
        }
        downloadTasks = downloadTasks.filter { protectedResourceIDs.contains($0.key) }

        for id in ids {
            if protectedResourceIDs.contains(id) {
                continue
            }
            if case .cached = statesByResourceID[id] {
                continue
            } else {
                statesByResourceID[id] = .none
            }
        }

        PreviewPlaybackLogger.log("cancelAllPreloads ids=\(ids.sorted())")
    }

    public func cacheState(for resourceID: String) -> PreviewAssetCacheState {
        statesByResourceID[resourceID] ?? .none
    }

    public func removeAllCache() async {
        cancelAllPreloads()
        statesByResourceID.removeAll()
        await fileCache.removeAll()
        PreviewPlaybackLogger.log("removeAllCache")
    }

    public func debugDumpState() async {
        let keys = statesByResourceID.keys.sorted()
        PreviewPlaybackLogger.log("asset repository states keys=\(keys)")
        let total = await fileCache.currentCacheSizeInBytes()
        PreviewPlaybackLogger.log("asset repository cacheSize=\(total) bytes")
    }

    private func startDownloadIfNeeded(
        for playable: PreviewPlayable,
        protectFromCancellation: Bool
    ) async {
        if let local = await fileCache.cachedFileURLIfExists(
            for: playable.resourceID,
            remoteURL: playable.videoURL
        ) {
            statesByResourceID[playable.resourceID] = .cached(localFileURL: local)
            protectedResourceIDs.remove(playable.resourceID)
            return
        }

        if protectFromCancellation {
            protectedResourceIDs.insert(playable.resourceID)
        }

        if downloadTasks[playable.resourceID] != nil {
            return
        }

        statesByResourceID[playable.resourceID] = .downloading(progress: nil)
        PreviewPlaybackLogger.log("start preload download resourceID=\(playable.resourceID) url=\(playable.videoURL.absoluteString)")

        let resourceID = playable.resourceID
        let task = Task { [weak self] in
            guard let self else { return }

            do {
                let (tempURL, _) = try await self.session.download(from: playable.videoURL)

                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }

                let local = try await self.fileCache.storeDownloadedFile(
                    tempFileURL: tempURL,
                    resourceID: resourceID,
                    remoteURL: playable.videoURL
                )

                await self.fileCache.trimIfNeeded()

                // 如果任务期间已经被替换/取消，不再回写
                guard self.downloadTasks[resourceID] != nil else {
                    return
                }

                self.statesByResourceID[resourceID] = .cached(localFileURL: local)
                self.downloadTasks.removeValue(forKey: resourceID)
                self.protectedResourceIDs.remove(resourceID)

                PreviewPlaybackLogger.log("finish preload download resourceID=\(resourceID) local=\(local.path)")
            } catch is CancellationError {
                self.downloadTasks.removeValue(forKey: resourceID)
                if case .cached = self.statesByResourceID[resourceID] {
                } else {
                    self.statesByResourceID[resourceID] = .none
                }
                self.protectedResourceIDs.remove(resourceID)
                PreviewPlaybackLogger.log("preload download cancelled resourceID=\(resourceID)")
            } catch {
                self.downloadTasks.removeValue(forKey: resourceID)
                self.statesByResourceID[resourceID] = .failed(description: error.localizedDescription)
                self.protectedResourceIDs.remove(resourceID)
                PreviewPlaybackLogger.log("preload download failed resourceID=\(resourceID) error=\(error.localizedDescription)")
            }
        }

        downloadTasks[playable.resourceID] = task
    }
}

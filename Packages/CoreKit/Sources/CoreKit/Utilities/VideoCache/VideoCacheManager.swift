//
//  VideoCacheManager.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/20.
//

import Foundation
import CryptoKit
import AVFoundation

public final class VideoCachePlayer {
    
    @MainActor
    public static func player(for remoteURL: URL) -> AVPlayer {

        let cache = VideoCacheManager.shared
        var playURL = remoteURL
        if !remoteURL.isFileURL {
             playURL = cache.cachedOrRemoteURL(for: remoteURL)
        }
        // 先播
        let player = AVPlayer(url: playURL)
        
        // 再后台下载
        if playURL == remoteURL && !remoteURL.isFileURL {
            cache.startDownloadIfNeeded(remoteURL)
        }

        player.isMuted = false
        player.actionAtItemEnd = .none
        return player
    }
}

@MainActor
public final class VideoCacheManager {

    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    
    // 状态控制
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var waitingQueue: [URL] = [] // 等待下载的队列
    private let maxConcurrentTasks = 3   // 最大并发数
    
    public static let shared = VideoCacheManager()
    
    private init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let cacheDirectory = cacheRoot.appendingPathComponent("video-cache", isDirectory: true)

            if !fileManager.fileExists(atPath: cacheDirectory.path) {
                try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            }
            self.cacheDirectory = cacheDirectory
        }
    }

    // MARK: - Public

    public func localURL(for remoteURL: URL) -> URL {
        let key = cacheKey(for: remoteURL)
        return cacheDirectory.appendingPathComponent("\(key).mp4")
    }

    public func isCached(_ remoteURL: URL) -> Bool {
        fileManager.fileExists(atPath: localURL(for: remoteURL).path)
    }

    public func cachedOrRemoteURL(for remoteURL: URL) -> URL {
        let local = localURL(for: remoteURL)
        return fileManager.fileExists(atPath: local.path) ? local : remoteURL
    }
    
    public func startDownloadIfNeeded(_ remoteURL: URL) {
        let key = cacheKey(for: remoteURL)
        
        // 1. 检查是否已经缓存、正在下载、或已在等待队列中
        guard !isCached(remoteURL) else { return }
        if activeTasks[key] != nil || waitingQueue.contains(remoteURL) {
            return
        }
        
        // 2. 加入等待队列并尝试调度
        waitingQueue.append(remoteURL)
        dequeueNextTask()
    }
    
    /// 取消下载任务（从等待队列移除，或取消正在下载的 Task）
    public func cancelDownload(for remoteURL: URL) {
        let key = cacheKey(for: remoteURL)
        
        // 1. 如果任务还在等待队列中，直接移除，无需消耗并发名额
        if let index = waitingQueue.firstIndex(of: remoteURL) {
            waitingQueue.remove(at: index)
            #if DEBUG
            DLLog("🛑 Cancelled waiting task: \(remoteURL.lastPathComponent)")
            #endif
            return
        }
        
        // 2. 如果任务正在下载，直接 cancel
        if let task = activeTasks[key] {
            task.cancel()
            // ⚠️ 注意：调用 cancel() 会触发 URLSession 的回调，并抛出 NSURLErrorCancelled 错误。
            // 因为我们在 executeDownload 中使用了 defer，
            // 那个回调会自动将任务从 activeTasks 中移除，并调用 dequeueNextTask() 启动下一个。
            // 所以这里不需要手动清理字典。
            #if DEBUG
            DLLog("🛑 Cancelled active task: \(remoteURL.lastPathComponent)")
            #endif
        }
    }
    
    /// 显式下载视频并等待完成，返回本地存储的 URL
    @discardableResult
    public func downloadVideo(url: URL) async throws -> URL {
        // 1. 如果已经缓存，直接返回
        if isCached(url) {
            return localURL(for: url)
        }
        
        // 2. 启动下载任务（如果没在下载的话）
        startDownloadIfNeeded(url)
        
        // 3. 使用通知桥接到 async/await
        return try await withCheckedThrowingContinuation { continuation in
            var successObserver: NSObjectProtocol?
            var failureObserver: NSObjectProtocol?
            
            // 清理监听器的闭包
            let cleanUp = {
                if let s = successObserver { NotificationCenter.default.removeObserver(s) }
                if let f = failureObserver { NotificationCenter.default.removeObserver(f) }
            }
            
            // 监听成功
            successObserver = NotificationCenter.default.addObserver(forName: .videoDidCache, object: nil, queue: .main) { notif in
                if let cachedURL = notif.userInfo?["url"] as? URL, cachedURL == url {
                    cleanUp()
                    continuation.resume(returning: self.localURL(for: url))
                }
            }
            
            // 监听失败
            failureObserver = NotificationCenter.default.addObserver(forName: .videoDownloadFailed, object: nil, queue: .main) { notif in
                if let failedURL = notif.userInfo?["url"] as? URL, failedURL == url {
                    cleanUp()
                    continuation.resume(throwing: URLError(.cannotOpenFile))
                }
            }
        }
    }
    
    // MARK: - Private Core
    
    private func dequeueNextTask() {
        // 如果当前运行的任务没满，且队列里还有东西
        while activeTasks.count < maxConcurrentTasks, !waitingQueue.isEmpty {
            let nextURL = waitingQueue.removeFirst()
            executeDownload(nextURL)
        }
    }
    
    private func executeDownload(_ remoteURL: URL) {
        let key = cacheKey(for: remoteURL)
        let request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        
        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                defer {
                    self.activeTasks.removeValue(forKey: key)
                    self.dequeueNextTask()
                }
                
                if let error = error {
                    // 2. 更新：下载失败时发送通知
                    NotificationCenter.default.post(name: .videoDownloadFailed, object: nil, userInfo: ["url": remoteURL, "error": error])
                    
#if DEBUG
                    let nsError = error as NSError
                    if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                        DLLog("❌ Video download failed: \(remoteURL.lastPathComponent)")
                    }
#endif
                    return
                }
                
                guard let tempURL = tempURL else { return }
                
                let destination = self.localURL(for: remoteURL)
                do {
                    if self.fileManager.fileExists(atPath: destination.path) {
                        try self.fileManager.removeItem(at: destination)
                    }
                    try self.fileManager.moveItem(at: tempURL, to: destination)
                    
#if DEBUG
                    DLLog("✅ Video cached: \(remoteURL.lastPathComponent)")
#endif
                    // 成功通知
                    NotificationCenter.default.post(name: .videoDidCache, object: nil, userInfo: ["url": remoteURL])
                } catch {
                    // 移动文件失败也发送失败通知
                    NotificationCenter.default.post(name: .videoDownloadFailed, object: nil, userInfo: ["url": remoteURL])
                }
            }
        }
        
        activeTasks[key] = task
        task.resume()
    }

    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension Notification.Name {
    public static let videoDidCache = Notification.Name("videoDidCache")
    public static let videoDownloadFailed = Notification.Name("videoDownloadFailed")
}

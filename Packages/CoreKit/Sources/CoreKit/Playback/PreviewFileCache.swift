//
//  PreviewFileCache.swift
//

import Foundation
import CryptoKit

public actor PreviewFileCache {
    public struct Config: Sendable {
        public let directoryName: String
        public let maxCacheSizeInBytes: Int64

        public init(
            directoryName: String = "preview_video_cache",
            maxCacheSizeInBytes: Int64 = 500 * 1024 * 1024
        ) {
            self.directoryName = directoryName
            self.maxCacheSizeInBytes = maxCacheSizeInBytes
        }
    }

    private let config: Config
    private let fileManager: FileManager
    private let cacheDirectoryURL: URL

    public init(config: Config = .init(), fileManager: FileManager = .default) throws {
        self.config = config
        self.fileManager = fileManager

        let base = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(config.directoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        self.cacheDirectoryURL = dir
    }

    public func localFileURL(for resourceID: String, remoteURL: URL) -> URL {
        let ext = sanitizedExtension(from: remoteURL)
        let safeName = safeFileName(for: resourceID)
        return cacheDirectoryURL.appendingPathComponent("\(safeName).\(ext)")
    }

    public func cachedFileURLIfExists(for resourceID: String, remoteURL: URL) -> URL? {
        let localURL = localFileURL(for: resourceID, remoteURL: remoteURL)
        guard fileManager.fileExists(atPath: localURL.path) else { return nil }
        touchFileIfNeeded(at: localURL)
        return localURL
    }

    public func storeDownloadedFile(
        tempFileURL: URL,
        resourceID: String,
        remoteURL: URL
    ) throws -> URL {
        let destination = localFileURL(for: resourceID, remoteURL: remoteURL)

        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: tempFileURL, to: destination)
        touchFileIfNeeded(at: destination)
        return destination
    }

    public func removeFileIfExists(for resourceID: String, remoteURL: URL) {
        let localURL = localFileURL(for: resourceID, remoteURL: remoteURL)
        if fileManager.fileExists(atPath: localURL.path) {
            try? fileManager.removeItem(at: localURL)
        }
    }

    public func currentCacheSizeInBytes() -> Int64 {
        let files = (try? fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var total: Int64 = 0
        for url in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    public func trimIfNeeded() {
        let total = currentCacheSizeInBytes()
        guard total > config.maxCacheSizeInBytes else { return }

        let files = (try? fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey
            ],
            options: [.skipsHiddenFiles]
        )) ?? []

        let regularFiles: [(url: URL, modifiedAt: Date, size: Int64)] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey
            ]) else {
                return nil
            }

            guard values.isRegularFile == true else { return nil }

            return (
                url: url,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                size: Int64(values.fileSize ?? 0)
            )
        }

        let sorted = regularFiles.sorted { $0.modifiedAt < $1.modifiedAt }

        var current = total
        for file in sorted {
            guard current > config.maxCacheSizeInBytes else { break }
            try? fileManager.removeItem(at: file.url)
            current -= file.size
        }
    }

    public func removeAll() {
        let files = (try? fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in files {
            try? fileManager.removeItem(at: url)
        }
    }

    private func touchFileIfNeeded(at url: URL) {
        let now = Date()
        try? fileManager.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }

    private func safeFileName(for resourceID: String) -> String {
        let digest = SHA256.hash(data: Data(resourceID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func sanitizedExtension(from remoteURL: URL) -> String {
        let ext = remoteURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if ext.isEmpty { return "mp4" }

        let filtered = ext.lowercased().filter {
            $0.isLetter || $0.isNumber
        }

        return filtered.isEmpty ? "mp4" : filtered
    }
}


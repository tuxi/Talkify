//
//  VideoStructureStore.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/6/11.
//

import Foundation

/// Sandbox-backed cache for `VideoStructure` results.
///
/// 和 `MotionProfileStore` 同模式：按视频文件 key 缓存 JSON，
/// 避免同一视频重复做 OCR + ASR 提取。文件极小（几 KB），放
/// Application Support 目录，iCloud 不同步。
public final class VideoStructureStore: Sendable {

    public static let shared = VideoStructureStore()

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory

        directory = base.appendingPathComponent("VideoStructures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func save(_ structure: VideoStructure, for key: String) {
        do {
            let data = try encoder.encode(structure)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            #if DEBUG
            print("[VideoStructureStore] save failed for \(key): \(error)")
            #endif
        }
    }

    public func load(for key: String) -> VideoStructure? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? decoder.decode(VideoStructure.self, from: data)
    }

    public func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(sanitized(key)).appendingPathExtension("json")
    }

    private func sanitized(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(String.UnicodeScalarView(
            key.unicodeScalars.map { allowed.contains($0) ? $0 : "_" }
        ))
    }

    /// 和 `MotionProfileStore.key(for:)` 相同策略：
    /// 文件名 + 字节大小 + 修改时间。
    public static func key(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size  = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.lastPathComponent)-\(size)-\(Int(mtime))"
    }
}

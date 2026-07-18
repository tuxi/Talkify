//
//  MotionProfileStore.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/6/8.
//

import Foundation

/// Sandbox-backed cache for `[MotionSegment]` energy profiles.
///
/// PRD §2.1: once an asset is profiled, its lightweight, read-only curve is
/// persisted so re-opening the same clip skips re-extraction. Profiles live under
/// Application Support (excluded from iCloud backup is unnecessary — they're tiny
/// and regenerable) as one JSON file per asset key.
public struct MotionProfileStore: Sendable {

    public static let shared = MotionProfileStore()

    private let directory: URL

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory

        directory = base.appendingPathComponent("MotionProfiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func save(_ segments: [MotionSegment], for key: String) {
        do {
            let data = try JSONEncoder().encode(segments)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            #if DEBUG
            print("[MotionProfileStore] save failed for \(key): \(error)")
            #endif
        }
    }

    public func load(for key: String) -> [MotionSegment]? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? JSONDecoder().decode([MotionSegment].self, from: data)
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

    /// Stable per-file key (name + byte size + mtime). PhotosPicker re-imports get a
    /// fresh UUID filename each time, so this won't dedup across separate imports of
    /// the same library asset — it's enough to round-trip a single imported file.
    public static func key(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size  = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.lastPathComponent)-\(size)-\(Int(mtime))"
    }
}

//
//  SharedImportInbox.swift
//  Talkify
//
//  Created by Codex on 2026/7/22.
//

#if os(iOS)
import Foundation

/// 主 App 与 Share Extension 之间的 App Group Inbox 协议。
///
/// 请求在创建工作区前会先从 `<id>` 原子移动到 `.processing-<id>`，避免 Sheet
/// dismiss、App active 通知和清理失败造成重复消费。
enum SharedImportInbox {
    static let appGroupID = "group.com.objc.chat"
    private static let inboxDirectoryName = "SharedImportInbox"
    private static let manifestName = "manifest.json"
    private static let payloadDirectoryName = "Payload"
    private static let processingPrefix = ".processing-"
    private static let consumedDefaultsKey = "shared-import-consumed-v1"
    private static let deferredDefaultsKey = "shared-import-deferred-v1"

    struct Request: Codable, Identifiable, Sendable {
        let version: Int
        let id: String
        var suggestedName: String
        let createdAt: Date
        let items: [Item]
    }

    struct Item: Codable, Sendable {
        let name: String
        let isDirectory: Bool
    }

    struct Claim: Sendable {
        let request: Request
        fileprivate let directoryURL: URL
    }

    /// 返回当前应该自动提示的请求；被“稍后”的请求在到期前不会出现。
    static func pendingRequests(now: Date = .now) -> [Request] {
        guard let inboxURL else { return [] }
        recoverAbandonedClaims(in: inboxURL)
        let consumedIDs = Set(consumedRecords().keys)
        let deferred = deferredRecords()
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return directories.compactMap { directory in
            guard let request = readRequest(in: directory) else { return nil }
            if consumedIDs.contains(request.id) {
                try? FileManager.default.removeItem(at: directory)
                return nil
            }
            if let deferredUntil = deferred[request.id], deferredUntil > now.timeIntervalSince1970 {
                return nil
            }
            return request
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    /// 在开始 copy-in 前领取请求。移动发生在同一个 App Group volume 内，是原子的。
    static func claim(_ request: Request) throws -> Claim {
        guard let inboxURL,
              let source = requestDirectoryURL(for: request.id)
        else { throw InboxError.appGroupUnavailable }
        let destination = inboxURL.appendingPathComponent(
            processingPrefix + request.id,
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw InboxError.requestUnavailable
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        clearDeferred(request.id)
        return Claim(request: request, directoryURL: destination)
    }

    static func workspaceSourceURL(for claim: Claim) throws -> URL {
        let payload = claim.directoryURL.appendingPathComponent(payloadDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: payload.path) else {
            throw InboxError.requestUnavailable
        }
        if claim.request.items.count == 1, claim.request.items[0].isDirectory {
            let directory = payload.appendingPathComponent(
                claim.request.items[0].name,
                isDirectory: true
            )
            if FileManager.default.fileExists(atPath: directory.path) {
                return directory
            }
        }
        return payload
    }

    /// 先持久化幂等标记，再尽力清理 payload。清理失败也不会再次提示。
    static func complete(_ claim: Claim) {
        markConsumed(claim.request.id)
        try? FileManager.default.removeItem(at: claim.directoryURL)
    }

    /// 创建失败时恢复请求，允许用户重试。
    static func restore(_ claim: Claim) {
        guard !isConsumed(claim.request.id),
              let destination = requestDirectoryURL(for: claim.request.id),
              FileManager.default.fileExists(atPath: claim.directoryURL.path),
              !FileManager.default.fileExists(atPath: destination.path)
        else { return }
        try? FileManager.default.moveItem(at: claim.directoryURL, to: destination)
    }

    /// “稍后”是持久化语义，不会因 App 再次 active 而失效。
    static func deferRequest(_ request: Request, for interval: TimeInterval = 24 * 60 * 60) {
        var records = deferredRecords()
        records[request.id] = Date.now.addingTimeInterval(interval).timeIntervalSince1970
        defaults.set(records, forKey: deferredDefaultsKey)
    }

    /// 用户明确放弃请求。先标记 consumed，删除失败也不会再弹出。
    static func discard(_ request: Request) {
        markConsumed(request.id)
        if let directory = requestDirectoryURL(for: request.id) {
            try? FileManager.default.removeItem(at: directory)
        }
        if let inboxURL {
            let processing = inboxURL.appendingPathComponent(
                processingPrefix + request.id,
                isDirectory: true
            )
            try? FileManager.default.removeItem(at: processing)
        }
    }

    private static func recoverAbandonedClaims(in inboxURL: URL) {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        for processingURL in directories where processingURL.lastPathComponent.hasPrefix(processingPrefix) {
            guard let request = readRequest(in: processingURL) else { continue }
            if isConsumed(request.id) {
                try? FileManager.default.removeItem(at: processingURL)
                continue
            }
            guard let pendingURL = requestDirectoryURL(for: request.id),
                  !FileManager.default.fileExists(atPath: pendingURL.path)
            else { continue }
            try? FileManager.default.moveItem(at: processingURL, to: pendingURL)
        }
    }

    private static func readRequest(in directory: URL) -> Request? {
        let manifestURL = directory.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let request = try? decoder.decode(Request.self, from: data),
              request.version == 1,
              !request.items.isEmpty,
              FileManager.default.fileExists(atPath: directory
                  .appendingPathComponent(payloadDirectoryName, isDirectory: true).path)
        else { return nil }
        return request
    }

    private static var inboxURL: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return nil }
        return container.appendingPathComponent(inboxDirectoryName, isDirectory: true)
    }

    private static func requestDirectoryURL(for id: String) -> URL? {
        inboxURL?.appendingPathComponent(id, isDirectory: true)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static func consumedRecords() -> [String: TimeInterval] {
        defaults.dictionary(forKey: consumedDefaultsKey)?.compactMapValues {
            ($0 as? NSNumber)?.doubleValue
        } ?? [:]
    }

    private static func deferredRecords() -> [String: TimeInterval] {
        defaults.dictionary(forKey: deferredDefaultsKey)?.compactMapValues {
            ($0 as? NSNumber)?.doubleValue
        } ?? [:]
    }

    private static func isConsumed(_ id: String) -> Bool {
        consumedRecords()[id] != nil
    }

    private static func markConsumed(_ id: String) {
        let cutoff = Date.now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970
        var records = consumedRecords().filter { $0.value >= cutoff }
        records[id] = Date.now.timeIntervalSince1970
        defaults.set(records, forKey: consumedDefaultsKey)
        clearDeferred(id)
    }

    private static func clearDeferred(_ id: String) {
        var records = deferredRecords()
        guard records.removeValue(forKey: id) != nil else { return }
        defaults.set(records, forKey: deferredDefaultsKey)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private enum InboxError: LocalizedError {
        case appGroupUnavailable
        case requestUnavailable

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                return TalkifyLocalized.string("import.cannot_access")
            case .requestUnavailable:
                return TalkifyLocalized.string("import.materials_gone")
            }
        }
    }
}
#endif

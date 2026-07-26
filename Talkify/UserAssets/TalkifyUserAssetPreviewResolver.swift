import Foundation
import AgentKit

actor TalkifyUserAssetPreviewResolver: UserAssetPreviewResolving {
    private struct Entry: Sendable {
        let url: URL
        let usableUntil: Date
    }

    private let api: any UserAssetAPIProtocol
    private let accountScope: @Sendable () -> String
    private var cachedScope: String?
    private var cache: [Int64: Entry] = [:]

    init(
        api: any UserAssetAPIProtocol,
        accountScope: @escaping @Sendable () -> String
    ) {
        self.api = api
        self.accountScope = accountScope
    }

    func previewURL(for asset: UserAssetRef) async throws -> URL {
        let scope = accountScope()
        if cachedScope != scope {
            cache.removeAll()
            cachedScope = scope
        }
        if let entry = cache[asset.assetID], entry.usableUntil > Date() {
            return entry.url
        }

        let remote = try await api.asset(id: asset.assetID)
        guard accountScope() == scope,
              remote.status == "active",
              remote.assetKind == "image",
              remote.contentType == "image/jpeg" || remote.contentType == "image/png",
              let urlString = remote.url,
              let url = URL(string: urlString),
              let expiresAt = remote.urlExpiresAt,
              expiresAt > Date() else {
            throw TalkifyUserAssetError.unavailable
        }
        // OSS 签名 URL 可能返回 http://，升级为 https:// 以避免
        // WKWebView 混合内容拦截。OSS 签名对 scheme 不敏感。
        let secureURL = url.absoluteString.hasPrefix("http://")
            ? URL(string: "https://" + url.absoluteString.dropFirst(7)) ?? url
            : url

        cache[asset.assetID] = Entry(
            url: secureURL,
            usableUntil: expiresAt.addingTimeInterval(-30)
        )
        return secureURL
    }

    func clearCache() {
        cache.removeAll()
        cachedScope = nil
    }
}

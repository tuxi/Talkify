//
//  PreviewPlayable.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import Foundation
import CryptoKit

public struct PreviewPlayable: Identifiable, Hashable, Sendable {
    /// 当前页面 / section / cell 的展示实例 ID
    public let id: String
    
    /// 资源级唯一标识，用于本地缓存
    public let resourceID: String
    
    /// 远端视频地址（通常是 OSS）
    public let videoURL: URL
    
    public let coverURL: URL?
    public let muted: Bool
    public let shouldLoop: Bool

    public init(
        id: String,
        resourceID: String? = nil,
        videoURL: URL,
        coverURL: URL? = nil,
        muted: Bool = true,
        shouldLoop: Bool = true
    ) {
        self.id = id
        self.resourceID = resourceID ?? Self.defaultResourceID(for: videoURL)
        self.videoURL = videoURL
        self.coverURL = coverURL
        self.muted = muted
        self.shouldLoop = shouldLoop
    }
}

public extension PreviewPlayable {
    static func defaultResourceID(for url: URL) -> String {
        normalizedResourceID(from: url.absoluteString)
    }
    
    static func normalizedResourceID(from raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }}

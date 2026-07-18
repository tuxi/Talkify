//
//  AccountInfo.swift
//  AgentKit
//
//  用户基本信息 —— 从 Gateway JWT claims 解析。
//

import Foundation

/// 用户基本信息。
///
/// 从 Gateway 签发的 JWT payload 中解析。不包含敏感字段。
/// `SubscriptionTier` 只出现在 `AccountInfo` 和 `UsageInfo` 中，
/// **不进入** Runtime 或 `Credential` 的 `metadata`。
public struct AccountInfo: Codable, Sendable, Equatable {
    public let userId: String
    public let email: String?
    public let displayName: String?
    public let subscriptionTier: SubscriptionTier

    public init(
        userId: String,
        email: String? = nil,
        displayName: String? = nil,
        subscriptionTier: SubscriptionTier = .free
    ) {
        self.userId = userId
        self.email = email
        self.displayName = displayName
        self.subscriptionTier = subscriptionTier
    }
}

/// 订阅等级。
public enum SubscriptionTier: String, Codable, Sendable, Equatable, CaseIterable {
    case free
    case pro
    case pro5x = "pro_5x"
    case pro20x = "pro_20x"
    case power
    case ultimate
    case team
    case enterprise
}

// MARK: - JWT Parsing

extension AccountInfo {
    /// 从 Gateway JWT payload 构造 AccountInfo。
    /// 尽力解析，缺失字段使用默认值。
    init(from jwtPayload: [String: Any]) {
        self.userId = (jwtPayload["sub"] as? String)
            ?? (jwtPayload["user_id"] as? String)
            ?? "unknown"
        self.email = jwtPayload["email"] as? String
        self.displayName = (jwtPayload["nickname"] as? String)
            ?? (jwtPayload["name"] as? String)
        self.subscriptionTier = (jwtPayload["tier"] as? String)
            .flatMap(SubscriptionTier.init(rawValue:)) ?? .free
    }
}

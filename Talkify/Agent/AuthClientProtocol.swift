//
//  AuthClientProtocol.swift
//  AgentKit
//
//  Gateway 认证 API 的抽象 —— 生产用 URLSession，测试用 Mock。
//

import Foundation
import AgentKit

// MARK: - AuthClientProtocol

/// Gateway 认证 API 的抽象。
///
/// 生产实现：`URLSessionAuthClient`（HTTP 调用 Gateway API）。
/// 测试实现：`MockAuthClient`。
///
/// 调用方：仅 `AccountManager`。不对 UI 层暴露。
public protocol AuthClientProtocol: Sendable {
    /// 密码登录。
    func login(email: String, password: String) async throws -> AuthResponse
    /// 密码注册。
    func register(email: String, password: String, displayName: String?) async throws -> AuthResponse
    /// Apple 登录。
    func loginWithApple(identityToken: String, authorizationCode: String, email: String?, givenName: String?, familyName: String?) async throws -> AuthResponse
    /// 匿名注册。
    func registerAnonymous() async throws -> AuthResponse
    /// 刷新 token。
    func refresh(refreshToken: String) async throws -> AuthResponse
    /// 登出（通知服务端使 token 失效）。
    func logout(accessToken: String) async throws
    /// 获取用量。
    func getUsage(accessToken: String) async throws -> UsageInfo
    /// 获取用户资料（可选）。
    func getProfile(accessToken: String) async throws -> AccountInfo
    /// 获取可用模型列表。
    func getModels(accessToken: String) async throws -> ModelsResponse
}

// MARK: - Types

/// 登录/刷新响应。
public struct AuthResponse: Codable, Sendable {
    /// JWT access token
    public let accessToken: String
    /// Refresh token（用于刷新）
    public let refreshToken: String
    /// access token 过期时间（Unix 秒）
    public let accessExp: Int64
    /// refresh token 过期时间（Unix 秒）
    public let refreshExp: Int64
    /// 是否新注册
    public let isNew: Bool
    /// 用户 ID
    public let userId: Int
    /// 用户展示名（登录时返回）
    public let nickname: String?

    /// access token 过期时间 → Date
    public var expiresAt: Date {
        Date(timeIntervalSince1970: TimeInterval(accessExp))
    }
}

/// 用量信息。
public struct UsageInfo: Codable, Sendable {
    /// `weekly_only` 发布后固定为 weekly。保留该字段是为了兼容旧响应，UI 不应展示它。
    public let quotaPolicy: QuotaPolicy?
    public let fiveHour: Units?
    public let weekly: Units
    /// 付费方案的订阅周期上限；Free 用户为 nil。
    public let subscriptionCycle: Units?
    /// 后端的兼容别名。新界面一律优先使用 `subscriptionCycle`。
    public let monthly: Units?
    public let byModel: [ModelUsage]?
    public let purchasedUnits: Int
    public let currentFundingSource: FundingSource?
    public let resetCards: ResetCardSummary?
    public let mode: UsageMode
    public let tier: SubscriptionTier
    
    public struct Units: Codable, Sendable {
        public let unitsUsed: Int
        public let unitsLimit: Int
        public let tokensUsed: Int
        public let utilizationPct: Float64
        public let resetsAt: String
        
        enum CodingKeys: String, CodingKey {
            case unitsUsed = "units_used"
            case unitsLimit = "units_limit"
            case tokensUsed = "tokens_used"
            case utilizationPct = "utilization_pct"
            case resetsAt = "resets_at"
        }
    }
    
    public struct ModelUsage: Codable, Sendable, Identifiable {
        public let model: String
        public let unitsUsed: Int
        public let tokensUsed: Int
        public let callCount: Int

        public var id: String { model }
        
        enum CodingKeys: String, CodingKey {
            case model
            case unitsUsed = "units_used"
            case tokensUsed = "tokens_used"
            case callCount = "call_count"
        }
    }

    public struct ResetCardSummary: Codable, Sendable {
        public let availableCount: Int
        public let active: ResetCard?
        public let items: [ResetCard]

        enum CodingKeys: String, CodingKey {
            case availableCount = "available_count"
            case active, items
        }
    }

    public struct ResetCard: Codable, Sendable, Identifiable {
        public let cardID: String
        public let grantUnits: Int
        public let remainingUnits: Int
        public let planCodeSnapshot: String?
        public let source: String?
        public let status: Status
        public let issuedAt: String?
        public let expiresAt: String?
        public let consumedAt: String?
        public let windowEndsAt: String?

        public var id: String { cardID }

        public enum Status: String, Codable, Sendable { case available, consumed, expired, revoked }

        enum CodingKeys: String, CodingKey {
            case cardID = "card_id"
            case grantUnits = "grant_units"
            case remainingUnits = "remaining_units"
            case planCodeSnapshot = "plan_code_snapshot"
            case source, status
            case issuedAt = "issued_at"
            case expiresAt = "expires_at"
            case consumedAt = "consumed_at"
            case windowEndsAt = "window_ends_at"
        }
    }

    public enum UsageMode: String, Codable, Sendable {
        case managed
        case byok
    }

    public enum QuotaPolicy: String, Codable, Sendable { case weeklyOnly = "weekly_only" }

    public enum FundingSource: String, Codable, Sendable {
        case subscription, resetCard = "reset_card", purchased, campaign, adminGrant = "admin_grant"
    }

    /// 付费用户展示订阅周期；Free 用户不会回退到废弃月字段。
    public var cycle: Units? { subscriptionCycle ?? monthly }

    public var availableResetCards: [ResetCard] {
        (resetCards?.items ?? []).filter { $0.status == .available }
    }

    enum CodingKeys: String, CodingKey {
        case weekly, monthly, mode, tier, byModel = "by_model"
        case fiveHour = "five_hour"
        case quotaPolicy = "quota_policy"
        case subscriptionCycle = "subscription_cycle"
        case purchasedUnits = "purchased_units"
        case currentFundingSource = "current_funding_source"
        case resetCards = "reset_cards"
    }
}

// MARK: - Errors

public enum AuthError: Error, LocalizedError {
    case notAuthenticated
    case noRefreshToken
    case refreshFailed
    case networkError(Error)
    case invalidResponse
    case serverError(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:       return "未登录。"
        case .noRefreshToken:         return "无法刷新：缺少 refresh token。"
        case .refreshFailed:          return "Token 刷新失败，请重新登录。"
        case .networkError(let e):    return "网络错误：\(e.localizedDescription)"
        case .invalidResponse:        return "服务器响应无效。"
        case .serverError(let c, let m): return "[\(c)] \(m)"
        }
    }
}

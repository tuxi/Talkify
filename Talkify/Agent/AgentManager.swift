//
//  AgentManager.swift
//  AgentKit
//

import Foundation
import AgentKit

#if canImport(CryptoKit)
import CryptoKit
#endif
import CoreKit

// MARK: - AgentManager

/// 用户身份管理器。
///
/// 使用 `@MainActor` + `@Observable` 供 SwiftUI 直接观察。
/// 依赖 `AuthClientProtocol`（Gateway API）+ `CredentialStore`（Keychain）。
///
/// Token 刷新采用双层策略（参考 AWS SDK credential cache）：
///   Layer 1 (Timer)：过期前 5 分钟主动刷新。
///   Layer 2 (Lazy)：每次 `gatewayCredential()` 前检查，即将过期则立即刷新。
///   macOS 睡眠 / iOS 后台冻结可能导致 timer 错过 → lazy refresh 兜底。
@MainActor
@Observable
public final class AgentManager {

    
    let apiProvider: ApiProvider
    // MARK: - Published State
    public private(set) var usage: UsageInfo?
    public private(set) var isRedeemingResetCard = false
    public private(set) var usageError: String?
    private var redeemIdempotencyKeys: [String: String] = [:]

    // MARK: - Dependencies

    private var refreshTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        apiProvider: ApiProvider,
    ) {
        self.apiProvider = apiProvider
    }

    // MARK: - Usage

    public func fetchUsage() {
        Task {
            do {
                let usage: UsageInfo = try await apiProvider.request(endpoint: AgentApi.usage)
                self.usage = usage
                self.usageError = nil
            } catch {
                self.usageError = error.localizedDescription
                DLLog(error)
            }
        }
    }

    public func refreshResetCards() {
        Task {
            do {
                let cards: UsageInfo.ResetCardSummary = try await apiProvider.request(endpoint: AgentApi.resetCards)
                guard let usage else { return }
                self.usage = UsageInfo(
                    quotaPolicy: usage.quotaPolicy, fiveHour: usage.fiveHour, weekly: usage.weekly,
                    subscriptionCycle: usage.subscriptionCycle, monthly: usage.monthly, byModel: usage.byModel,
                    purchasedUnits: usage.purchasedUnits, currentFundingSource: usage.currentFundingSource,
                    resetCards: cards, mode: usage.mode, tier: usage.tier
                )
            } catch {
                self.usageError = error.localizedDescription
                DLLog(error)
            }
        }
    }

    public func redeemResetCard(_ card: UsageInfo.ResetCard) {
        guard !isRedeemingResetCard else { return }
        isRedeemingResetCard = true
        usageError = nil
        let key = redeemIdempotencyKeys[card.cardID] ?? UUID().uuidString
        redeemIdempotencyKeys[card.cardID] = key
        Task {
            defer { isRedeemingResetCard = false }
            do {
                let _: ResetCardRedeemResponse = try await apiProvider.request(
                    endpoint: AgentApi.redeemResetCard(id: card.cardID, idempotencyKey: key)
                )
                redeemIdempotencyKeys[card.cardID] = nil
                fetchUsage()
            } catch {
                usageError = error.localizedDescription
                DLLog(error)
            }
        }
    }
    
    public func fetchModels() async throws -> ModelsResponse {
        let models: ModelsResponse = try await apiProvider.request(endpoint: AgentApi.models)
        return models
    }
}

/// 核销结果的字段由网关演进；客户端只需确认 `data` 是有效对象，随后刷新 usage。
private struct ResetCardRedeemResponse: Codable, Sendable {}

// MARK: - JWT Decoding

/// 解码 JWT payload（不做签名验证 —— Gateway 已验证）。
/// 客户端只读 claims，不依赖格式稳定（见 agent-gateway-api-v1.md 附录 B）。
private func decodeJWTPayload(_ token: String) throws -> [String: Any] {
    let segments = token.components(separatedBy: ".")
    guard segments.count >= 2 else {
        throw AuthError.invalidResponse
    }
    let base64 = segments[1]
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: padded),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AuthError.invalidResponse
    }
    return json
}

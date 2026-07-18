//
//  BillingViewData.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/19.
//

import Foundation

// MARK: - 订阅状态（客户端统一领域模型）
public enum SubscriptionStatus: Equatable, Sendable {
    case guest                       // 未登录
    case inactive                   // 已登录但未订阅
    case active(ActiveSubscription) // 当前有效
    case expired(ExpiredSubscription) // 已过期
    case gracePeriod(ActiveSubscription) // 宽限期（后端未来可扩展）
}

// MARK: - 有效订阅信息
public struct ActiveSubscription: Equatable, Sendable {
    public let name: String?
    public let expiredAt: Int?
    
    public init(name: String?, expiredAt: Int?) {
        self.name = name
        self.expiredAt = expiredAt
    }
}

// MARK: - 过期订阅信息
public struct ExpiredSubscription: Equatable, Sendable {
    public let name: String?
    public let expiredAt: Int?
    
    public init(name: String?, expiredAt: Int?) {
        self.name = name
        self.expiredAt = expiredAt
    }
}

public extension BillingWallet {

    var subscriptionStatus: SubscriptionStatus {
        if subscriptionActive {
            return .active(
                .init(
                    name: currentSubscription,
                    expiredAt: subscriptionExpiredAt
                )
            )
        }

        // 没激活，但有到期时间 = 曾经订阅过
        if let expiredAt = subscriptionExpiredAt {
            return .expired(
                .init(
                    name: currentSubscription,
                    expiredAt: expiredAt
                )
            )
        }

        return .inactive
    }
}

public extension BillingEntitlements {

    var subscriptionStatus: SubscriptionStatus {
        if subscriptionActive {
            return .active(
                .init(
                    name: currentSubscription,
                    expiredAt: subscriptionExpiredAt
                )
            )
        }

        if let expiredAt = subscriptionExpiredAt {
            return .expired(
                .init(
                    name: currentSubscription,
                    expiredAt: expiredAt
                )
            )
        }

        return .inactive
    }
}

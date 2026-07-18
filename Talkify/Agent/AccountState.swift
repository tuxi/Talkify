//
//  AccountState.swift
//  AgentKit
//
//  用户账号状态枚举。
//

import Foundation

/// 用户账号状态。
///
/// `AccountManager` 持有并管理此状态的生命周期。
/// UI 层通过 `AccountManager.state` 观察并据此渲染。
public enum AccountState: Sendable, Equatable {
    /// 未登录。Settings 显示 "登录" 入口；agent 使用 BYOK 或不可用。
    case anonymous
    /// 已登录。持有完整的用户信息 + Gateway JWT。
    case authenticated(AccountInfo)
    /// Token 已过期且刷新失败。提示重新登录。
    case expired(AccountInfo)
    /// 离线。有缓存的 credential 但无法连接 Gateway 验证。
    case offline(AccountInfo)

    // MARK: - Accessors

    public var accountInfo: AccountInfo? {
        switch self {
        case .anonymous:                    return nil
        case .authenticated(let info):      return info
        case .expired(let info):            return info
        case .offline(let info):            return info
        }
    }

    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    public var needsReauth: Bool {
        if case .expired = self { return true }
        return false
    }
}

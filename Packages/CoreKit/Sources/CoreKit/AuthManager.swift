//
//  AuthManager.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/1.
//

import Foundation
import Observation
import Alamofire
import Security

public enum AuthError: Error {
    case notLoggedIn
    case isRefreshing
    case refreshUnauthorized      // 刷新令牌失效，应该退出登录
    case refreshFailed(Error)     // 其他刷新失败，不应该直接退出
    case unknown
}

// 登录成功响应
public struct AuthToken: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let accessExp: Int
    public let refreshExp: Int
    public let userId: Int
    public let role: Int
    public let isNew: Bool
    public let accountType: String?
    public let nickname: String?
    public let avatarUrl: String?

    /// 从 API 响应 JSON 或 JWT payload 中获取 account_type
    private var resolvedAccountType: String? {
        if let accountType { return accountType }
        return jwtPayload?["account_type"] as? String
    }

    public var isAnonymous: Bool { resolvedAccountType == "anonymous" }
    // nil 视为正式账号（兼容服务端尚未返回 account_type 字段的旧 token）
    public var isRegistered: Bool { resolvedAccountType == nil || resolvedAccountType == "registered" }

    /// 解析 JWT payload（不验证签名，仅提取字段）
    private var jwtPayload: [String: Any]? {
        let segments = accessToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// accessToken 过期时间
    public var accessExpireDate: Date {
        Date(timeIntervalSince1970: TimeInterval(accessExp))
    }

    /// refreshToken 过期时间
    var refreshExpireDate: Date {
        Date(timeIntervalSince1970: TimeInterval(refreshExp))
    }

    /// accessToken 剩余时间
    var accessRemainingSeconds: TimeInterval {
        accessExpireDate.timeIntervalSinceNow
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accessExp = "access_exp"
        case refreshExp = "refresh_exp"
        case userId = "user_id"
        case role
        case isNew = "is_new"
        case accountType = "account_type"
        case nickname
        case avatarUrl = "avatar_url"
    }

    /// accessToken 是否过期
    /// - Parameter seconds: 提前多少秒判定为过期（用于提前刷新）
    public func isExpired(within seconds: TimeInterval = 0) -> Bool {
        return Date().addingTimeInterval(seconds) >= accessExpireDate
    }

    /// refreshToken 是否过期
    public func isRefreshExpired() -> Bool {
        return Date() >= refreshExpireDate
    }
}

public struct AuthTokenStore: @unchecked Sendable {
    private let keychainGroupId: String?
    private let legacyStore: UserDefaults
    private let keyPrefix = "com.objc.dreamlog.authKey"
    private let legacyKeyPrefix = "com.objc.dreamlog.authKey"

    public init(keychainGroupId: String? = nil, legacyStore: UserDefaults = .standard) {
        self.keychainGroupId = keychainGroupId
        self.legacyStore = legacyStore
    }

    public func load(environment: AppEnvironment) -> AuthToken? {
        // 1. 优先从 Keychain 读取
        if let token = loadFromKeychain(environment: environment) {
            return token
        }
        // 2. 从旧 UserDefaults 迁移
        if let token = loadFromUserDefaults(environment: environment) {
            try? saveToKeychain(token, environment: environment)
            removeFromUserDefaults(environment: environment)
            return token
        }
        return nil
    }

    public func save(_ token: AuthToken?, environment: AppEnvironment) {
        guard let token else {
            clear(environment: environment)
            return
        }
        try? saveToKeychain(token, environment: environment)
        removeFromUserDefaults(environment: environment)
    }

    public func clear(environment: AppEnvironment) {
        deleteFromKeychain(environment: environment)
        removeFromUserDefaults(environment: environment)
    }

    // MARK: - Keychain

    private func keychainQuery(environment: AppEnvironment) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainKey(for: environment),
        ]
        if let keychainGroupId {
            query[kSecAttrAccessGroup] = keychainGroupId
        }
        return query
    }

    private func loadFromKeychain(environment: AppEnvironment) -> AuthToken? {
        var query = keychainQuery(environment: environment)
        query[kSecReturnData] = kCFBooleanTrue!
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AuthToken.self, from: data)
    }

    private func saveToKeychain(_ token: AuthToken, environment: AppEnvironment) throws {
        deleteFromKeychain(environment: environment)

        var query = keychainQuery(environment: environment)
        query[kSecValueData] = try JSONEncoder().encode(token)
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "AuthTokenStore", code: Int(status))
        }
    }

    private func deleteFromKeychain(environment: AppEnvironment) {
        let query = keychainQuery(environment: environment)
        SecItemDelete(query as CFDictionary)
    }

    private func keychainKey(for environment: AppEnvironment) -> String {
        "\(keyPrefix).\(environment.rawValue)"
    }

    // MARK: - Legacy UserDefaults migration

    private func loadFromUserDefaults(environment: AppEnvironment) -> AuthToken? {
        let key = "\(legacyKeyPrefix).\(environment.rawValue)"
        guard let str = legacyStore.string(forKey: key),
              let data = str.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AuthToken.self, from: data)
    }

    private func removeFromUserDefaults(environment: AppEnvironment) {
        let key = "\(legacyKeyPrefix).\(environment.rawValue)"
        legacyStore.removeObject(forKey: key)
    }
}


/// 专门负责令牌刷新期间的控流状态管理
/// 使用 @unchecked Sendable 是因为内部通过 NSLock 确保了绝对的线程安全
private final class TokenState: @unchecked Sendable {
    private let lock = NSLock()
    private var isRefreshing = false
    private var waiters: [@Sendable (RetryResult) -> Void] = []
    
    /// 供非隔离域使用的 Token 快照
    private var _currentToken: AuthToken?
    
    var currentToken: AuthToken? {
        lock.withLock { _currentToken }
    }
    
    func updateToken(_ token: AuthToken?) {
        lock.withLock { _currentToken = token }
    }
    
    /// 添加等待者并决定是否由当前调用者触发刷新
    func addWaiterAndCheckRefresh(_ completion: @escaping @Sendable (RetryResult) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        waiters.append(completion)
        if isRefreshing { return false }
        
        isRefreshing = true
        return true
    }
    
    /// 提取所有等待者并重置状态
    func reset() -> [@Sendable (RetryResult) -> Void] {
        lock.lock()
        defer { lock.unlock() }
        
        let pending = waiters
        waiters.removeAll()
        isRefreshing = false
        return pending
    }

    /// 仅查询刷新状态（用于 ensureValidToken）
    var refreshingStatus: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRefreshing
    }
}

@Observable
@MainActor // 确保所有 UI 属性修改均在主线程
public final class AuthManager: Sendable {

    // MARK: - UI 状态
    public var isLoggedIn: Bool { token != nil }
    public var showLoginSheet: Bool = false
    public private(set) var token: AuthToken?
    public var isAdmin: Bool { token?.role == 5090 }
    public var accountType: String? { token?.accountType }
    public var isAnonymous: Bool { token?.isAnonymous ?? false }
    public var isRegistered: Bool { token?.isRegistered ?? false }
    public var displayNickname: String? { token?.nickname }
    public var displayAvatarUrl: String? { token?.avatarUrl }

    // MARK: - 并发控流
    // state 是 Sendable 且不依赖 MainActor，因此可以安全地在 nonisolated 方法中使用
    private let state = TokenState()

    private let tokenStore: AuthTokenStore
    private var environment: AppEnvironment
    public typealias RefreshTokenHandler = @Sendable (AuthToken) async throws -> AuthToken
    private let refreshTokenHandler: RefreshTokenHandler

    public typealias AnonymousRegisterHandler = @Sendable () async throws -> AuthToken
    private let anonymousRegisterHandler: AnonymousRegisterHandler?
    private var isPerformingAnonymousRegister = false

    private var isEnableAnonymousRegistration = false
    
    public init(
        environment: AppEnvironment = .prod,
        tokenStore: AuthTokenStore = AuthTokenStore(),
        refreshTokenHandler: @escaping RefreshTokenHandler,
        anonymousRegisterHandler: AnonymousRegisterHandler? = nil
    ) {
        self.environment = environment
        self.tokenStore = tokenStore
        self.refreshTokenHandler = refreshTokenHandler
        self.anonymousRegisterHandler = anonymousRegisterHandler
        // 初始化时从持久化加载
        if let token = tokenStore.load(environment: environment) {
            self.token = token
            // 同步初始状态到 state
            state.updateToken(token)
        }
    }

    // MARK: - 状态更新逻辑 (MainActor)
    public func updateLoginState(token: AuthToken?) {
        self.token = token // 更新主线程状态
        state.updateToken(token) // 同步到线程安全包装器
        if let token {
            tokenStore.save(token, environment: environment)
            self.showLoginSheet = false
        } else {
            tokenStore.clear(environment: environment)
        }
    }

    public func requireLogin() {
        if !isRegistered {
            showLoginSheet = false
            DispatchQueue.main.async {
                self.showLoginSheet = true
            }
        }
    }

    /// 退出登录：清空 token 后自动创建新的匿名身份
    public func logout() {
        updateLoginState(token: nil)
        _ = state.reset()
        Task { await performAnonymousRegistration() }
    }

    /// Token 过期处理：匿名静默重建，正式弹出登录
    public func handleTokenExpired() {
        if token?.isAnonymous == true {
            Task { await silentReRegister() }
        } else {
            updateLoginState(token: nil)
            _ = state.reset()
            showLoginSheet = true
        }
    }

    /// 静默重建匿名身份（refresh token 过期时调用）
    public func silentReRegister() async {
        updateLoginState(token: nil)
        _ = state.reset()
        await performAnonymousRegistration()
    }

    /// 在启动时确保存在一个有效身份（匿名或正式）
    public func ensureInitialIdentity() async {
        if token != nil { return }
        await performAnonymousRegistration()
    }

    // MARK: - 匿名注册
    private func performAnonymousRegistration() async {
        if !isEnableAnonymousRegistration {
            return
        }
        guard let handler = anonymousRegisterHandler, !isPerformingAnonymousRegister else { return }
        isPerformingAnonymousRegister = true
        defer { isPerformingAnonymousRegister = false }

        do {
            let token = try await handler()
            updateLoginState(token: token)
            DLLog("AuthManager: 匿名注册成功 user_id=\(token.userId)")
        } catch {
            DLLog("AuthManager: 匿名注册失败: \(error)")
        }
    }

    public func switchEnvironment(_ environment: AppEnvironment) {
        self.environment = environment
        let token = tokenStore.load(environment: environment)
        self.token = token
        state.updateToken(token)
        _ = state.reset()
        showLoginSheet = false
    }
    
    // MARK: - 拦截器专用：非隔离访问接口
    
    /// 提供给拦截器同步获取 Token 的方法
    nonisolated public var accessToken: String? {
        state.currentToken?.accessToken
    }
    
    /// 提供给拦截器同步获取 RefreshToken 的方法
    nonisolated public var refreshToken: String? {
        state.currentToken?.refreshToken
    }

    // MARK: - 拦截器专用接口 (Non-isolated)
    
    nonisolated public func addWaiterAndCheckRefresh(_ completion: @escaping @Sendable (RetryResult) -> Void) -> Bool {
        state.addWaiterAndCheckRefresh(completion)
    }
    
    nonisolated public func handleRefreshResult(_ result: RetryResult) {
        let waiters = state.reset()
        waiters.forEach { $0(result) }
    }
    
    // MARK: - 令牌自动校验逻辑
    public func ensureValidToken() async throws -> String {
        guard let currentToken = self.token else {
            await performAnonymousRegistration()
            if let newToken = self.token {
                return newToken.accessToken
            }
            self.showLoginSheet = true
            throw AuthError.notLoggedIn
        }

        // token 过期60秒前刷新
        if currentToken.isExpired(within: 60) {
            do {
                DLLog("AuthManager: Token 即将过期，开始刷新...")
                let newToken = try await refreshTokenHandler(currentToken)
                updateLoginState(token: newToken)
                return newToken.accessToken
            } catch {
                if error.isUnauthorized401 {
                    DLLog("AuthManager: refresh token 已失效")
                    if currentToken.isAnonymous {
                        DLLog("AuthManager: 匿名用户，静默重建身份")
                        await silentReRegister()
                        if let newToken = self.token {
                            return newToken.accessToken
                        }
                        throw AuthError.notLoggedIn
                    } else {
                        DLLog("AuthManager: 正式用户，退出登录")
                        handleTokenExpired()
                        throw AuthError.refreshUnauthorized
                    }
                } else {
                    DLLog("AuthManager: 刷新失败，但不是登录失效: \(error)")
                    throw AuthError.refreshFailed(error)
                }
            }
        }
        return currentToken.accessToken
    }
}

extension AuthManager {
    /// 核心优化：非隔离域的安全 Token 获取方法
    /// 1. 如果 Token 有效，直接返回。
    /// 2. 如果 Token 过期且正在刷新，自动排队等待刷新结果。
    /// 3. 如果 Token 过期且无人在刷，自动触发刷新逻辑。
    nonisolated public func getValidAccessToken() async throws -> String {
        // 1. 检查当前快照
        guard let token = state.currentToken else {
            // 如果没登录，需要切回主线程弹窗（UI 操作）
//            await MainActor.run { self.requireLogin() }
            throw AuthError.notLoggedIn
        }
        
        // 2. 检查是否过期 (预留 60 秒缓冲)
        if !token.isExpired(within: 60) {
            return token.accessToken // 有效则直接返回
        }
        
        // 3. 过期了，利用 waiter 机制排队，防止并发刷新
        return try await withCheckedThrowingContinuation { continuation in
            let isFirstTrigger = addWaiterAndCheckRefresh { result in
                // 当 handleRefreshResult 被调用时，所有排队者会进到这里
                switch result {
                case .retry: // 刷新成功了
                    if let freshToken = self.accessToken {
                        continuation.resume(returning: freshToken)
                    } else {
                        continuation.resume(throwing: AuthError.notLoggedIn)
                    }
                case .doNotRetry: // 刷新彻底失败
                    continuation.resume(throwing: AuthError.refreshFailed(AuthError.unknown))
                case .doNotRetryWithError(let error):
                    continuation.resume(throwing: AuthError.refreshFailed(error))
                @unknown default:
                    continuation.resume(throwing: AuthError.unknown)
                }
            }
            
            // 如果是第一个进来的，负责触发真正的刷新任务
            if isFirstTrigger {
                Task {
                    do {
                        // 调用主线程的 worker 逻辑，它现在不再自锁了
                        let token = try await self.ensureValidToken()
                        DLLog("AuthManager.Token 有效，通知大家去拿新 Token 重试自己的接口:", token)
                        // 刷新成功：通知所有等待者 .retry (去拿新 token)
                        self.handleRefreshResult(.retry)
                    } catch {
                        // 刷新失败：通知所有等待者 .doNotRetry (停止请求)
                        self.handleRefreshResult(.doNotRetry)
                    }
                }
            }
        }
    }
}

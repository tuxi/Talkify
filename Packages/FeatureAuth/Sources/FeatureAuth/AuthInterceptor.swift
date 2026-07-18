//
//  AuthInterceptor.swift
//  FeatureAuth
//
//  Created by xiaoyuan on 2026/3/1.
//

import Foundation
import Alamofire
import CoreKit

/// 安全的认证拦截器（Swift 6 完全兼容）
/// 认证拦截器（Swift 6 兼容，控流逻辑委托给 AuthManager）
public final class AuthInterceptor: RequestInterceptor, @unchecked Sendable {
    // MARK: - 成员变量
    private let authManager: AuthManager
    
    // MARK: - 初始化
    public init(
        authManager: AuthManager
    ) {
        self.authManager = authManager
    }
    
    // MARK: - RequestAdapter（添加 Authorization 头）
    public func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @Sendable @escaping (Result<URLRequest, Error>) -> Void
    ) {
        var request = urlRequest
        if let token = authManager.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        completion(.success(request))
    }
    
    // MARK: - RequestRetrier（401 重试，控流委托给 AuthManager）
    public func retry(
        _ request: Request,
        for session: Session,
        dueTo error: Error,
        completion: @Sendable @escaping (RetryResult) -> Void
    ) {
           
        // 1. 校验状态码
        guard let afError = error as? AFError,
              afError.responseCode == 401 else {
            completion(.doNotRetry)
            return
        }
        // 2. 若请求本身是 refresh 接口，绝不重试。匿名静默重建，正式弹出登录
        if request.request?.url?.path.contains("auth/refresh") == true {
            Task { @MainActor in
                authManager.handleTokenExpired()
            }
            completion(.doNotRetry)
            return
        }

        // 3. 如果连 Refresh Token 都没有
        //    匿名用户静默重建，正式用户弹出登录
        guard authManager.refreshToken != nil else {
            Task { @MainActor in
                authManager.handleTokenExpired()
            }
            completion(.doNotRetry)
            return
        }
        
        // 4. 尝试刷新逻辑
        // 委托给 AuthManager 判断是否需要刷新（全局控流）
        if authManager.addWaiterAndCheckRefresh(completion) {
            Task {
                do {
                    // 触发刷新逻辑
                    _ = try await authManager.ensureValidToken()
                    authManager.handleRefreshResult(.retry)
                } catch {
                    authManager.handleRefreshResult(.doNotRetry)
                }
            }
        }
    }
}

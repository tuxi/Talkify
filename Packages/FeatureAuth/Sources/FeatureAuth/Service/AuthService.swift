//
//  AuthService.swift
//  FeatureAuth
//
//  Created by xiaoyuan on 2026/3/1.
//

import Foundation
import CoreKit

// AliOSS 的临时凭证
struct STSTokenRes: Codable, Sendable {
    let accessKeyId: String
    let accessKeySecret: String
    let securityToken: String
    let expiration: String
    let userID: String
    
    enum CodingKeys: String, CodingKey {
        case accessKeyId = "access_key_id"
        case accessKeySecret = "access_key_secret"
        case securityToken = "security_token"
        case expiration = "expiration"
        case userID = "user_id"
    }
}

public final class AuthService: @unchecked Sendable {
    private let apiProvider: ApiProvider
    // 缓存当前的 Token
    private var cachedToken: STSTokenRes?
    
    public init(api: ApiProvider) {
        self.apiProvider = api
    }
    
    public func sendPhoneCode(phone: String) async throws -> PhoneCodeSendResponse {
        let endpoint = AuthApi.sendPhoneCode(phone: phone)
        return try await apiProvider.request(endpoint: endpoint)
    }
    
    public func loginByPhoneCode(phone: String, code: String) async throws -> AuthToken {
        let endpoint = AuthApi.loginByPhoneCode(phone: phone, code: code)
        let response: AuthToken = try await apiProvider.request(endpoint: endpoint)
        return response
    }
    
    public func loginByOneTap(accessToken: String, outId: String? = nil) async throws -> AuthToken {
        let endpoint = AuthApi.loginByOneTap(accessToken: accessToken, outId: outId)
        let response: AuthToken = try await apiProvider.request(endpoint: endpoint)
        return response
    }
    
    public func loginByApple(
        identityToken: String,
        authorizationCode: String,
        email: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil
    ) async throws -> AuthToken {
        let endpoint = AuthApi.loginByApple(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            email: email,
            givenName: givenName,
            familyName: familyName
        )
        let response: AuthToken = try await apiProvider.request(endpoint: endpoint)
        return response
    }

    public func sendBindPhoneCode(phone: String) async throws -> AuthActionResponse {
        let endpoint = AuthApi.sendBindPhoneCode(phone: phone)
        let response: AuthActionResponse = try await apiProvider.request(endpoint: endpoint)
        return response
    }

    public func confirmBindPhone(phone: String, code: String) async throws -> AuthActionResponse {
        let endpoint = AuthApi.confirmBindPhone(phone: phone, code: code)
        let response: AuthActionResponse = try await apiProvider.request(endpoint: endpoint)
        return response
    }

    public func bindApple(
        identityToken: String,
        authorizationCode: String,
        email: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil
    ) async throws -> AuthActionResponse {
        let endpoint = AuthApi.bindApple(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            email: email,
            givenName: givenName,
            familyName: familyName
        )
        let response: AuthActionResponse = try await apiProvider.request(endpoint: endpoint)
        return response
    }

    public func unbindApple() async throws -> AuthActionResponse {
        let endpoint = AuthApi.unbindApple
        let response: AuthActionResponse = try await apiProvider.request(endpoint: endpoint)
        return response
    }

    public func fetchSecurityStatus() async throws -> AuthSecurityStatus {
        try await apiProvider.request(endpoint: AuthApi.securityStatus)
    }
    
    public func loginByPassword(username: String, password: String) async throws -> AuthToken {
        let endpoint = AuthApi.loginByPassword(username: username, password: password)
        let response: AuthToken = try await apiProvider.request(endpoint: endpoint)
        return response
    }
    
    public func registerByPassword(username: String, password: String) async throws -> AuthToken {
        let endpoint = AuthApi.registerByPassword(username: username, password: password)
        let response: AuthToken = try await apiProvider.request(endpoint: endpoint)
        return response
    }
    
    public func anonymousRegister(deviceId: String) async throws -> AuthToken {
        let endpoint = AuthApi.anonymousRegister(deviceId: deviceId)
        return try await apiProvider.request(endpoint: endpoint)
    }

    public func logout() async throws {
        let endpoint = AuthApi.logout
        let _: ApiResponseDataPlaceholder = try await apiProvider.request(endpoint: endpoint)
    }

    func fetchSTSToken() async throws -> STSTokenRes {
        let endpoint = AuthApi.ossToken
        let token: STSTokenRes = try await apiProvider.request(endpoint: endpoint)
        return token
    }
    
    private func fetchSTSTokenFromServer() async throws -> STSTokenRes {
        // 如果 DeviceManager 是 MainActor，这里会安全异步等待
        // 执行请求
        let token: STSTokenRes = try await apiProvider.request(endpoint: AuthApi.ossToken)
        return token
    }
}


/// 使用 actor 代替 class，确保 cachedToken 的访问是线程安全的
public actor AppSTSProvider: OSSCredentialsProvider {
    
    /// 2. 状态变量受 actor 保护
    private var cachedToken: STSTokenRes?
    
    /// 3. 记录正在进行的任务，防止多个请求同时冲击后端（请求合并）
    private var activeTask: Task<STSTokenRes, Error>?
    private var apiProvider: ApiProvider
    
    public init(apiProvider: ApiProvider) {
        self.apiProvider = apiProvider

    }
    
    /// 实现 OSSCredentialsProvider 协议
    public func getCredentials() async throws -> OSSStsCredential {
        // 检查缓存
        if let token = cachedToken, !isExpired(token.expiration) {
            return OSSStsCredential(accessKeyId: token.accessKeyId, accessKeySecret: token.accessKeySecret, securityToken: token.securityToken, userId: token.userID)
        }
        
        // 如果当前没有正在抓取的任务，则启动一个
        if let existingTask = activeTask {
            let token = try await existingTask.value
            return OSSStsCredential(accessKeyId: token.accessKeyId, accessKeySecret: token.accessKeySecret, securityToken: token.securityToken, userId: token.userID)
        }
        
        // 创建新任务并缓存该 Task 本身
        let newTask = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchSTSTokenFromServer()
        }
        
        self.activeTask = newTask
        
        do {
            let token = try await newTask.value
            self.cachedToken = token
            self.activeTask = nil // 任务完成，清除引用
            return OSSStsCredential(accessKeyId: token.accessKeyId, accessKeySecret: token.accessKeySecret, securityToken: token.securityToken, userId: token.userID)
        } catch {
            self.activeTask = nil
            throw error
        }
    }
    
    /// 内部私有抓取逻辑
    private func fetchSTSTokenFromServer() async throws -> STSTokenRes {
        // 执行请求
        let token: STSTokenRes = try await apiProvider.request(endpoint: AuthApi.ossToken)
        return token
    }
    
    private func isExpired(_ expiration: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        // 阿里云返回格式通常带毫秒或不带，ISO8601DateFormatter 默认处理 Z 结尾
        guard let expireDate = formatter.date(from: expiration) else {
            return true
        }
        // 提前 5 分钟失效
        return expireDate < Date().addingTimeInterval(300)
    }
}

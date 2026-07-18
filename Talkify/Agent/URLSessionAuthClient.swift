//
//  URLSessionAuthClient.swift
//  AgentKit
//
//  AuthClientProtocol 的生产实现 —— 基于 URLSession 调用 Agent Gateway API。
//

import Foundation
import AgentKit

/// AuthClientProtocol 的 URLSession 实现。
///
/// 对应 `agent-gateway-api-v1.md` 的 Auth API。
/// 默认连接 `http://localhost:12221`（开发环境），通过 baseURL 覆盖。
public final class URLSessionAuthClient: AuthClientProtocol, Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// - Parameters:
    ///   - baseURL: Gateway 的 base URL（如 `https://agent.xxx.com`）。
    ///   - session: 自定义 URLSession（如测试 mock）。
    public init(baseURL: URL = URL(string: "http://localhost:12221")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
        self.encoder = JSONEncoder()
    }

    // MARK: - AuthClientProtocol

    public func login(email: String, password: String) async throws -> AuthResponse {
        let body: [String: String] = ["username": email, "password": password]
        return try await post("/api/v1/auth/login/password", body: body)
    }

    public func register(email: String, password: String, displayName: String?) async throws -> AuthResponse {
        var body: [String: String] = ["username": email, "password": password]
        if let displayName { body["nickname"] = displayName }
        return try await post("/api/v1/auth/register/password", body: body)
    }

    public func loginWithApple(
        identityToken: String,
        authorizationCode: String,
        email: String?,
        givenName: String?,
        familyName: String?
    ) async throws -> AuthResponse {
        var body: [String: String] = [
            "identity_token": identityToken,
            "authorization_code": authorizationCode,
        ]
        if let email { body["email"] = email }
        if let givenName { body["given_name"] = givenName }
        if let familyName { body["family_name"] = familyName }
        return try await post("/api/v1/auth/apple/login", body: body)
    }

    public func registerAnonymous() async throws -> AuthResponse {
        try await post("/api/v1/anonymous/register", body: Optional<String>.none)
    }

    public func refresh(refreshToken: String) async throws -> AuthResponse {
        let body = ["refresh_token": refreshToken]
        return try await post("/api/v1/auth/refresh", body: body)
    }

    public func logout(accessToken: String) async throws {
        var request = try makeRequest("POST", "/api/v1/auth/logout")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw AuthError.invalidResponse
        }
    }

    public func getUsage(accessToken: String) async throws -> UsageInfo {
        return try await get("/api/v1/agent/usage", accessToken: accessToken)
    }

    public func getProfile(accessToken: String) async throws -> AccountInfo {
        let wrapper: GatewayResponse<AccountInfo> = try await get("/api/v1/user/profile", accessToken: accessToken)
        guard let data = wrapper.data else {
            throw AuthError.invalidResponse
        }
        return data
    }

    public func getModels(accessToken: String) async throws -> ModelsResponse {
        let wrapper: GatewayResponse<ModelsResponse> = try await get("/api/v1/agent/models", accessToken: accessToken)
        guard let data = wrapper.data else {
            throw AuthError.invalidResponse
        }
        return data
    }

    // MARK: - HTTP Helpers

    private func makeRequest(_ method: String, _ path: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw AuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        DeviceContext.apply(to: &request)
        return request
    }

    private func post<T: Encodable>(_ path: String, body: T?) async throws -> AuthResponse {
        var request = try makeRequest("POST", path)
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        let wrapper = try decoder.decode(GatewayResponse<AuthResponse>.self, from: data)
        if let data = wrapper.data { return data }
        throw AuthError.serverError(code: wrapper.code, message: wrapper.msg)
    }

    private func get<T: Decodable>(_ path: String, accessToken: String) async throws -> T {
        var request = try makeRequest("GET", path)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        switch http.statusCode {
        case 200, 201: return
        case 401: throw AuthError.notAuthenticated
        case 429: throw AuthError.serverError(code: 429, message: "quota exceeded")
        case 500: throw AuthError.serverError(code: 500, message: "server error")
        default:  throw AuthError.serverError(code: http.statusCode, message: "")
        }
    }
}

// MARK: - Gateway Response Wrapper

/// Agent Gateway 统一响应格式。见 `agent-gateway-api-v1.md` §1.2。
private struct GatewayResponse<T: Decodable>: Decodable {
    let code: Int
    let msg: String
    let data: T?
}

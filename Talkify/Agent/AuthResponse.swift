//
//  AuthResponse.swift
//  CodeAgent
//
//  Dreamlog 账号安全状态和响应类型。从 Dreamlog 迁移。
//

import Foundation

public struct PhoneCodeSendResponse: Codable, Sendable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}

public struct AuthActionResponse: Codable, Sendable {
    public let success: Bool
    public let message: String?

    public init(success: Bool, message: String?) {
        self.success = success
        self.message = message
    }
}

public struct AuthSecurityStatus: Codable, Sendable {
    public let userID: Int
    public let phoneMasked: String?
    public let hasPhone: Bool
    public let hasApple: Bool
    public let hasPassword: Bool
    public let canBindPhone: Bool
    public let canBindApple: Bool
    public let canUnbindApple: Bool
    public let boundLoginMethods: [String]
    public let recommendedLoginMethods: [String]
    public let preferredLoginMethod: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case phoneMasked = "phone_masked"
        case hasPhone = "has_phone"
        case hasApple = "has_apple"
        case hasPassword = "has_password"
        case canBindPhone = "can_bind_phone"
        case canBindApple = "can_bind_apple"
        case canUnbindApple = "can_unbind_apple"
        case boundLoginMethods = "bound_login_methods"
        case recommendedLoginMethods = "recommended_login_methods"
        case preferredLoginMethod = "preferred_login_method"
    }
}

public enum LoginMethod: String, Codable, Sendable {
    case phoneCode
    case phoneOneTap
    case apple
}

public struct LastLoginContext: Codable, Sendable {
    public let method: LoginMethod
    public let phoneNumber: String?
    public let lastLoginAt: Date

    public init(method: LoginMethod, phoneNumber: String?, lastLoginAt: Date) {
        self.method = method
        self.phoneNumber = phoneNumber
        self.lastLoginAt = lastLoginAt
    }
}

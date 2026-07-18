//
//  AuthApi.swift
//  FeatureAuth
//
//  Created by xiaoyuan on 2026/3/1.
//

import Foundation
import CoreKit

public enum AuthApi: ApiEndpoint {
    case sendPhoneCode(phone: String)
    case loginByPhoneCode(phone: String, code: String)
    case loginByOneTap(accessToken: String, outId: String?)
    case loginByApple(
        identityToken: String,
        authorizationCode: String,
        email: String?,
        givenName: String?,
        familyName: String?
    )
    case sendBindPhoneCode(phone: String)
    case confirmBindPhone(phone: String, code: String)
    case bindApple(
        identityToken: String,
        authorizationCode: String,
        email: String?,
        givenName: String?,
        familyName: String?
    )
    case unbindApple
    case securityStatus
    
    // 兼容测试
    case loginByPassword(username: String, password: String)
    case registerByPassword(username: String, password: String)
    case logout
    case refreshToken(token: String)
    case cryptoTool(text: String, action: String)
    case ossToken
    case anonymousRegister(deviceId: String, deviceType: String = "ios")

    public var path: String {
        switch self {
        case .sendPhoneCode:
            return "auth/phone/send-code"
        case .loginByPhoneCode:
            return "auth/phone/login-by-code"
        case .loginByOneTap:
            return "auth/phone/login-by-one-tap"
        case .loginByApple:
            return "auth/apple/login"
        case .sendBindPhoneCode:
            return "auth/bind/phone/send-code"
        case .confirmBindPhone:
            return "auth/bind/phone/confirm"
        case .bindApple:
            return "auth/bind/apple"
        case .unbindApple:
            return "auth/unbind/apple"
        case .securityStatus:
            return "auth/security-status"
        case .loginByPassword:
            return "auth/login/password"
        case .logout:
            return "auth/logout"
        case .refreshToken:
            return "auth/refresh"
        case .cryptoTool:
            return "auth/tool/crypto"
        case .registerByPassword: return "auth/register/password"
        case .ossToken: return "auth/oss/sts"
        case .anonymousRegister: return "anonymous/register"
        }
    }
    
    public var method: HTTPMethod {
        switch self {
        case .ossToken, .securityStatus:
            return .get
        default:
            return .post
        }
    }
    
    public var parameters: [String : Sendable] {
        switch self {
        case .sendPhoneCode(let phone):
            return [
                "phone": phone
            ]
        case .loginByPhoneCode(let phone, let code):
            return [
                "phone": phone,
                "code": code
            ]
        case .loginByOneTap(let accessToken, let outId):
            var payload: [String: Sendable] = [
                "access_token": accessToken
            ]
            if let outId, !outId.isEmpty {
                payload["out_id"] = outId
            }
            return payload
        case .loginByApple(let identityToken, let authorizationCode, let email, let givenName, let familyName):
            var payload: [String: Sendable] = [
                "identity_token": identityToken,
                "authorization_code": authorizationCode
            ]
            if let email, !email.isEmpty {
                payload["email"] = email
            }
            if let givenName, !givenName.isEmpty {
                payload["given_name"] = givenName
            }
            if let familyName, !familyName.isEmpty {
                payload["family_name"] = familyName
            }
            return payload
        case .sendBindPhoneCode(let phone):
            return [
                "phone": phone
            ]
        case .confirmBindPhone(let phone, let code):
            return [
                "phone": phone,
                "code": code
            ]
        case .bindApple(let identityToken, let authorizationCode, let email, let givenName, let familyName):
            var payload: [String: Sendable] = [
                "identity_token": identityToken,
                "authorization_code": authorizationCode
            ]
            if let email, !email.isEmpty {
                payload["email"] = email
            }
            if let givenName, !givenName.isEmpty {
                payload["given_name"] = givenName
            }
            if let familyName, !familyName.isEmpty {
                payload["family_name"] = familyName
            }
            return payload
        case .unbindApple, .securityStatus:
            return [:]
            
        case .loginByPassword(let user, let pwd):
            return [
                "username": user,
                "password": pwd,
            ]
        case .registerByPassword(let username, let password):
            return [
                "username": username,
                "password": password,
            ]
        case .cryptoTool(let text, let action):
            return [
                "text": text,
                "action": action
            ]
        case .refreshToken(let token):
            return [
                "refresh_token": token
            ]
        case .logout, .ossToken:
            return [:]
        case .anonymousRegister:
            return [:]
        }
    }

    public var headers: [String: String] {
        switch self {
        case .anonymousRegister(let deviceId, let deviceType):
            return [
                "X-Device-ID": deviceId,
                "X-Device-Type": deviceType,
            ]
        default:
            return [:]
        }
    }

    public var encoding: ApiParameterEncoding { .json }
}

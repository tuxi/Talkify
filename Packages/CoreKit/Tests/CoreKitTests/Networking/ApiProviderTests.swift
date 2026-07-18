//
//  ApiProviderTests.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/2/28.
//

import XCTest
import Alamofire
@testable import CoreKit

struct User: Decodable, Sendable { let id: Int; let name: String }
struct UserEndpoint: ApiEndpoint {
    var path: String = "user"
    var method: HTTPMethod = .get
    var parameters: [String: Sendable] = [:]
}

final class ApiProviderTests: XCTestCase {
    
    // 1. 创建一个测试专用的配置
    struct TestConfig: ApiConfiguration {
        var isDebugLogEnabled: Bool = true
        var baseURL: URL = URL(string: "https://mock.api.com")!
        var commonHeaders: [String : String] = ["App-Version": "1.0"]
        var commonParameters: [String: Sendable] = ["platform": "iOS"]
        var timeout: TimeInterval = 5
        var decrypter: ApiDecrypter? = nil
        var interceptor: (any RequestInterceptor & Sendable)? = nil
    }

    var provider: ApiProvider!

    override func setUp() {
        super.setUp()
        // 2. 配置 Session 以使用 MockProtocol
        let configuration = URLSessionConfiguration.af.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        
        let log = NetworkLogger(enabled: true)
        
        let session = Session(configuration: configuration, eventMonitors: [log])
       
        // 3. 注入 Provider (假设你修改了 Provider 的 init 以支持传入 Session，或者在 Config 里支持)
        provider = ApiProvider(config: TestConfig(), session: session)
    }

    // 测试普通请求解析
    func testRequestSuccess() async throws {
        // 准备 Mock 数据
        let jsonString = """
        {
            "code": 0,
            "message": "success",
            "data": { "id": 123, "name": "Xiaoyuan" },
        }
        """
        let mockData = jsonString.data(using: .utf8)!
        
        MockURLProtocol.mockHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, mockData)
        }

        // 执行请求
        

        let user: User = try await provider.request(endpoint: UserEndpoint())
        
        XCTAssertEqual(user.name, "Xiaoyuan")
        XCTAssertEqual(user.id, 123)
    }

    // 测试业务错误码解析
    func testBusinessError() async throws {
        let jsonString = """
        { "code": 4001, "message": "Token Expired", "data": null }
        """
        MockURLProtocol.mockHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8)!)
        }

        do {
            let _: ApiResponseDataPlaceholder = try await provider.request(endpoint: UserEndpoint())
            XCTFail("应该抛出错误")
        } catch let APIError.businessError(code, message) {
            XCTAssertEqual(code, 4001)
            XCTAssertEqual(message, "Token Expired")
        } catch {
            XCTFail("抛出了错误的异常类型")
        }
    }
    
    
    func testLoginCaptchaMapping() async throws {
        // 1. 准备 Mock 响应数据
        let mockJSON = """
        {
          "code": 200,
          "msg": "success",
          "trace_id": "uuid-12345",
          "data": {
            "is_administrator": true,
            "is_anonymous": false,
            "is_new": true,
            "key": "test_key",
            "role": 1,
            "timeout": 3600,
            "token": "mock_token_string"
          }
        }
        """
        
        MockURLProtocol.mockHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, mockJSON.data(using: .utf8)!)
        }

        // 2. 执行请求 (注意：由于你的业务 code 是 200，记得修改 ApiResponse.isSuccess)
        let endpoint = AuthApi.loginCaptcha(phone: "18810181988", captcha: "1234")
        let result: LoginResponse = try await provider.request(endpoint: endpoint)

        // 3. 验证结果
        XCTAssertEqual(result.token, "mock_token_string")
        XCTAssertTrue(result.isAdministrator)
    }


    func testRealLocalLogin() async throws {
        // 1. 创建指向本地的配置
        struct LocalConfig: ApiConfiguration {
            var timeout: TimeInterval = 10
            
            var decrypter: (any CoreKit.ApiDecrypter)?
            
            var isDebugLogEnabled: Bool
            
            var baseURL: URL = URL(string: "http://127.0.0.1:12199")!
            var commonHeaders: [String : String] = ["accept": "application/json"]
            var commonParameters: [String: Sendable] = [:]
            var interceptor: (any RequestInterceptor & Sendable)? = nil
        }
        
        // 2. 使用真实的 Session (不传 MockURLProtocol)
        let realProvider = ApiProvider(config: LocalConfig(isDebugLogEnabled: true))
        
        // 3. 调用
        do {
            let endpoint = AuthApi.loginCaptcha(phone: "18810181988", captcha: "1234")
            let loginInfo: LoginResponse = try await realProvider.request(endpoint: endpoint)
            DLLog("✅ Login Success, Token: \(loginInfo.token)")
            XCTAssertNotNil(loginInfo.token)
        } catch {
            XCTFail("请求失败: \(error)")
        }
    }
}


struct LoginResponse: Decodable, Sendable {
    public let isAdministrator: Bool
    public let isAnonymous: Bool
    public let isNew: Bool
    public let key: String
    public let role: Int
    public let timeout: Int
    public let token: String

    enum CodingKeys: String, CodingKey {
        case isAdministrator = "is_administrator"
        case isAnonymous = "is_anonymous"
        case isNew = "is_new"
        case key, role, timeout, token
    }
}

enum AuthApi: ApiEndpoint {
    case loginCaptcha(phone: String, captcha: String)

    var path: String {
        switch self {
        case .loginCaptcha: return "api/v1/auth/login/captcha"
        }
    }

    var method: HTTPMethod { .post }

    var parameters: [String: Sendable] {
        switch self {
        case .loginCaptcha(let phone, let captcha):
            return ["phone": phone, "captcha": captcha]
        }
    }

    // 默认是 .json，匹配 cURL 中的 Content-Type: application/json
    var encoding: ApiParameterEncoding { .json }
}

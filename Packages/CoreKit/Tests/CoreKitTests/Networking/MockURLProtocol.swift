//
//  File.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/2/28.
//

import Foundation

class MockURLProtocol: URLProtocol {
    // 使用 nonisolated(unsafe) 告诉编译器你会在测试中手动保证其安全
    // 或者使用 @MainActor，但要注意 startLoading 是系统在后台线程调用的
    nonisolated(unsafe) static var mockHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }

    override func startLoading() {
        // 由于 startLoading 在后台线程，我们直接安全读取静态变量
        guard let handler = MockURLProtocol.mockHandler else {
            fatalError("MockURLProtocol: 必须在测试开始前设置 mockHandler")
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

//
//  NetworkLogger.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/2/28.
//

import Foundation
import Alamofire

final class NetworkLogger: EventMonitor, @unchecked Sendable {
    let isEnabled: Bool
    
    init(enabled: Bool) {
        self.isEnabled = enabled
    }

    // 当 Request 完成准备工作时调用
    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        guard isEnabled else { return }
        // 打印请求日志
        ApiLogger.log(request: urlRequest)
    }

    // 当请求结束时调用
    func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        guard isEnabled else { return }
        // 打印响应日志
        ApiLogger.log(responseData: response.data, url: response.request?.url)
    }
}

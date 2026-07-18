//
//  StringExt.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/20.
//

import Foundation

public struct DError: Error, LocalizedError {
    public var message: String
    
    public init(message: String) {
        self.message = message
    }
    
    public var errorDescription: String? {
        return message
    }
}

extension String {
    /// Base64字符串解析为字典
    /// - Parameter base64Str: 服务端返回的Base64编码字符串
    /// - Returns: 解析后的字典（失败返回nil）
    public func base64DecodedToDictionary() throws -> [String: Any] {
        try parseBase64ToDictionary(self)
    }
    
    private func parseBase64ToDictionary(_ base64Str: String?) throws -> [String: Any] {
        // 1. 空值判断
        guard let base64Str = base64Str, !base64Str.isEmpty else {
        
            throw DError(message: "Base64字符串为空")
        }
        
        // 2. 处理Base64填充和URL安全字符
        var processedStr = base64Str
        // 补充填充字符
        let padding = base64Str.count % 4
        if padding > 0 {
            let padStr = String(repeating: "=", count: 4 - padding)
            processedStr += padStr
        }
        // 替换URL安全字符
        processedStr = processedStr.replacingOccurrences(of: "-", with: "+")
        processedStr = processedStr.replacingOccurrences(of: "_", with: "/")
        
        // 3. Base64解码
        guard let decodeData = Data(base64Encoded: processedStr, options: .ignoreUnknownCharacters) else {
            throw DError(message: "Base64解码失败：\(base64Str)")
        }
        
        // 4. JSON解析为字典
        do {
            guard let result = try JSONSerialization.jsonObject(with: decodeData, options: .mutableContainers) as? [String: Any] else {
                throw DError(message: "JSON解析结果不是字典：\(String(data: decodeData, encoding: .utf8) ?? "")")
            }
            return result
        } catch {
            throw DError(message: "JSON解析失败：\(error)")
        }
    }
    
   public var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    public func toJSONObjectIfPossible() -> JSONValue? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        guard let data = trimmed.data(using: .utf8) else { return nil }
        
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            return JSONValue.from(any: object)
        } catch {
            return nil
        }
    }
}

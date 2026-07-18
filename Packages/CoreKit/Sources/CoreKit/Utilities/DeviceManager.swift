//
//  DeviceManager.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/2.
//

import Foundation
import Security

@Observable
@MainActor
public final class DeviceManager {
    
    private let keychainGroupId: String?
    
    // MARK: - 常量定义
    private enum Constants {
        /// Keychain中存储device_id的key
        static let keychainDeviceIdKey = "com.objc.dreamlog.device_id"
    }
    
    // MARK: - 私有属性
    /// 串行队列，保证线程安全
    private let queue = DispatchQueue(label: "com.objc.devicemanager.queue")
    /// 缓存的deviceId，避免重复读取Keychain
    private(set) var deviceId: String?
    
    // MARK: - 初始化
    public init(keychainGroupId: String) {
        self.keychainGroupId = keychainGroupId
    }
    
    // MARK: - 核心API
    
    /// 初始化device_id：优先从Keychain读取，无则生成新的并存储
    /// - Returns: 设备唯一标识device_id
    /// - Throws: 生成或读取失败时抛出异常
    public func initializeDeviceId() throws -> String {
        try queue.sync {
            // 1. 先从缓存读取
            if let cachedDeviceId = deviceId, !cachedDeviceId.isEmpty {
                return cachedDeviceId
            }
            
            // 2. 从系统Keychain读取
            if let existingDeviceId = readDeviceIdFromKeychain(), !existingDeviceId.isEmpty {
                self.deviceId = existingDeviceId
                return existingDeviceId
            }
            
            // 3. 生成新的device_id并存储
            let newDeviceId = generateDeviceId()
            // 存储到系统Keychain
            try saveDeviceIdToKeychain(deviceId: newDeviceId)
            // 更新缓存
            self.deviceId = newDeviceId
            
            return newDeviceId
        }
    }
    
    /// 重置device_id：清空现有值并生成新的
    /// - Returns: 新的device_id
    /// - Throws: 生成或存储失败时抛出异常
    public func resetDeviceId() throws -> String {
        try queue.sync {
            // 1. 清空Keychain和缓存
            deleteDeviceIdFromKeychain()
            self.deviceId = nil
            
            // 2. 生成新的device_id
            let newDeviceId = generateDeviceId()
            // 3. 存储新值到Keychain
            try saveDeviceIdToKeychain(deviceId: newDeviceId)
            self.deviceId = newDeviceId
            
            return newDeviceId
        }
    }
    
    /// 获取当前的device_id（如果未初始化会自动初始化）
    /// - Returns: 设备唯一标识
    /// - Throws: 初始化失败时抛出异常
    public func getDeviceId() throws -> String {
        if let deviceId = deviceId, !deviceId.isEmpty {
            return deviceId
        }
        return try initializeDeviceId()
    }
    
    public func getDeviceInfo() throws -> DeviceInfo {
        return DeviceInfo.create(with: try getDeviceId())
    }
    
    public func mustGetDeviceInfo() -> DeviceInfo {
        return DeviceInfo.create(with: try! getDeviceId())
    }
    
    // MARK: - 私有方法：Keychain操作（基于系统API）
    
    /// 保存device_id到系统Keychain
    /// - Parameter deviceId: 要存储的设备ID
    /// - Throws: 存储失败时抛出异常
    private func saveDeviceIdToKeychain(deviceId: String) throws {
        // 1. 先删除旧值（避免重复）
        deleteDeviceIdFromKeychain()
        
        // 2. 构建Keychain查询参数
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, // 通用密码类型
            kSecAttrAccount: Constants.keychainDeviceIdKey, // 唯一标识
            kSecValueData: deviceId.data(using: .utf8)!, // 要存储的数据
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock // 解锁后可访问（安全级别）
        ]
        
        // 可选：设置访问组（用于App Group共享）
        if let keychainGroupId = self.keychainGroupId {
            query[kSecAttrAccessGroup] = keychainGroupId
        }
        
        // 3. 写入Keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "DeviceManager", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "存储device_id到Keychain失败，状态码：\(status)"
            ])
        }
    }
    
    /// 从系统Keychain读取device_id
    /// - Returns: 存储的设备ID，nil表示未找到
    private func readDeviceIdFromKeychain() -> String? {
        // 1. 构建查询参数
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: Constants.keychainDeviceIdKey,
            kSecReturnData: kCFBooleanTrue!, // 返回数据
            kSecMatchLimit: kSecMatchLimitOne // 只返回一条
        ]
        
        // 2. 执行查询
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        // 3. 处理结果
        guard status == errSecSuccess,
              let data = result as? Data,
              let deviceId = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return deviceId
    }
    
    /// 从系统Keychain删除device_id
    private func deleteDeviceIdFromKeychain() {
        // 1. 构建删除参数
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: Constants.keychainDeviceIdKey
        ]
        
        // 2. 执行删除
        let _ = SecItemDelete(query as CFDictionary)
    }
    
    /// 生成稳定的device_id（基于UUID）
    /// - Returns: 唯一的device_id字符串
    private func generateDeviceId() -> String {
        // 方案：纯UUID（简单、唯一、推荐）
        let uuid = UUID().uuidString
        return uuid.replacingOccurrences(of: "-", with: "")
    }
}

// MARK: - 使用示例
//do {
//    // 初始化并获取device_id
//    let deviceId = try DeviceManager.shared.getDeviceId()
//    print("当前设备ID：\(deviceId)")
//    
//    // 重置device_id（按需调用）
//    // let newDeviceId = try DeviceManager.shared.resetDeviceId()
//    // print("新设备ID：\(newDeviceId)")
//} catch {
//    print("操作DeviceManager失败：\(error.localizedDescription)")
//}

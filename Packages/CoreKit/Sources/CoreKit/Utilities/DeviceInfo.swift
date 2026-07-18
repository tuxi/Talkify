//
//  DeviceInfo.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/2.
//


import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct DeviceInfo: Sendable {
    /// 设备唯一标识（外部传入）
    public let deviceId: String
    /// 设备类型（如 iOS, macOS）
    public let deviceType: String
    /// 设备名称（如 "iPhone 15 Pro" 或 "MacBook Pro"）
    public let deviceName: String
    /// 系统版本（如 "17.2" 或 "14.4"）
    public let osVersion: String
    /// App 版本号（如 "2.1.0"）
    public let appVersion: String
    public let buildVersion: String
    
    /// 自动识别设备类型
    public static func getDeviceType() -> String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return "Unknown"
        #endif
    }
    
    /// 获取设备名称
    public static func getDeviceName() -> String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.name
        #elseif os(macOS)
        // 在 macOS 上，ProcessInfo.processInfo.hostName 通常返回机器名
        // 或者使用 Host.current().localizedName (需 import Foundation)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown Device"
        #endif
    }
    
    /// 获取系统版本
    public static func getOSVersion() -> String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.systemVersion
        #else
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        #endif
    }
    
    /// 获取 App 版本号
    public static func getAppVersion() -> String {
        guard let infoDict = Bundle.main.infoDictionary,
              let version = infoDict["CFBundleShortVersionString"] as? String else {
            return "1.0.0"
        }
        return version
    }
    
    public static func getBuildVersion() -> String {
        guard let infoDict = Bundle.main.infoDictionary,
              let version = infoDict["CFBundleVersion"] as? String else {
            return "1"
        }
        return version
    }
    
    
    /// 快速创建 DeviceInfo 实例
    public static func create(with deviceId: String) -> DeviceInfo {
        return DeviceInfo(
            deviceId: deviceId,
            deviceType: getDeviceType(),
            deviceName: getDeviceName(),
            osVersion: getOSVersion(),
            appVersion: getAppVersion(),
            buildVersion: getBuildVersion()
        )
    }
    
    public static var isPadLayout: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }
}

extension DeviceInfo {
    /// 生成漂亮的 HTML 诊断信息卡片
    public var toHTMLString: String {
        return """
        <br><br>
        <hr style="border: none; border-top: 1px solid #E5E5EA; margin: 20px 0;">
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #3A3A3C; font-size: 14px; background-color: #F2F2F7; padding: 16px; border-radius: 12px; max-width: 500px; margin: 0 auto;">
            <div style="font-weight: bold; color: #1C1C1E; margin-bottom: 12px; font-size: 15px; border-bottom: 1px solid #E5E5EA; padding-bottom: 6px;">
                🤖 设备与应用信息 (Diagnostic Info)
            </div>
            <table style="width: 100%; border-collapse: collapse; line-height: 22px;">
                <tr>
                    <td style="color: #8E8E93; width: 90px; padding: 2px 0;">应用版本</td>
                    <td style="font-weight: 500; color: #1C1C1E;">\(appVersion) (\(buildVersion))</td>
                </tr>
                <tr>
                    <td style="color: #8E8E93; padding: 2px 0;">设备型号</td>
                    <td style="color: #1C1C1E;">\(deviceName)</td>
                </tr>
                <tr>
                    <td style="color: #8E8E93; padding: 2px 0;">系统版本</td>
                    <td style="color: #1C1C1E;">\(deviceType) \(osVersion)</td>
                </tr>
                <tr>
                    <td style="color: #8E8E93; padding: 2px 0;">设备标识</td>
                    <td style="font-family: Menlo, Monaco, Consolas, monospace; font-size: 11px; color: #636366; word-break: break-all;">\(deviceId)</td>
                </tr>
            </table>
            <div style="font-size: 11px; color: #AEAEB2; margin-top: 12px; text-align: center;">
                * 请勿删除以上信息，它能帮我们更快解决您遇到的问题。
            </div>
        </div>
        """
    }
}

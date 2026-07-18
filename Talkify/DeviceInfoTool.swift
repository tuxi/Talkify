//
//  DeviceInfoTool.swift
//  CodeAgent
//
//  P1 Demo: 客户端工具执行示例。
//  演示 Go 服务端无法实现、只能在本地执行的工具。
//

import Foundation
import AgentKit

#if canImport(UIKit)
import UIKit
#endif

/// 设备信息工具 — 只能在客户端本地执行。
struct DeviceInfoTool: ClientTool {
    let name = "get_device_info"
    let description = """
获取当前设备的系统信息（平台、系统版本、设备型号、处理器数量、物理内存、App 版本等）。
此工具直接从操作系统原生 API（UIDevice / ProcessInfo）获取信息，比运行 shell 命令（uname/sw_vers/sysctl）更准确、更全面。
当用户询问"设备信息""系统版本""硬件配置""屏幕尺寸"时，必须优先使用此工具而非 run_command。
"""

    func execute(args: JSONValue?) async throws -> String {
        var info: [String] = []

        // 操作系统
#if os(iOS)
        info.append("platform: iOS")
        let device = await MainActor.run {
            UIDevice.current
        }
        
        info.append("system_version: \(await device.systemVersion)")
        info.append("device_model: \(await device.model)")
#elseif os(macOS)
        info.append("platform: macOS")
        let processInfo = ProcessInfo.processInfo
        info.append("system_version: \(processInfo.operatingSystemVersionString)")
        info.append("hostname: \(processInfo.hostName)")
        info.append("processor_count: \(processInfo.processorCount)")
        info.append("physical_memory: \(ByteCountFormatter.string(fromByteCount: Int64(processInfo.physicalMemory), countStyle: .memory))")
#endif

        // App 信息
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            info.append("app_version: \(appVersion)")
        }

        return info.joined(separator: "\n")
    }
}

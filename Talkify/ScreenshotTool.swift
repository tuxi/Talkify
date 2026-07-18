//
//  ScreenshotTool.swift
//  CodeAgent
//
//  P1 Demo: 耗时客户端工具 — 屏幕截图（macOS 专用）。
//  使用 ScreenCaptureKit 原生 API，自动触发系统权限弹窗并等待用户授权。
//  iOS 不支持此工具（ScreenCaptureKit 仅在 macOS 上可用）。
//

#if os(macOS)

import Foundation
import ScreenCaptureKit
import AppKit
import AgentKit

/// 屏幕截图工具 — 使用 ScreenCaptureKit 原生 API。
/// 执行时间 2-3 秒（含权限等待），用于验证异步工具执行 + UI running 状态。
struct ScreenshotTool: ClientTool {
    let name = "take_screenshot"
    let description = "截取当前 Mac 主屏幕的完整截图并保存到临时 PNG 文件。返回截图文件的完整路径、大小和分辨率。适用场景：用户要求截图、屏幕捕获、保存当前屏幕内容。注意：首次使用会弹出系统权限对话框，用户需在系统设置中授予「屏幕录制」权限后重试。"

    var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "save_path": .object([
                    "type": .string("string"),
                    "description": .string("截图保存路径（可选，默认保存到临时目录）")
                ])
            ]),
            "required": .array([])
        ])
    }

    func execute(args: JSONValue?) async throws -> String {
        var outputPath: String
        if case .object(let dict) = args,
           case .string(let customPath) = dict["save_path"] {
            outputPath = customPath
        } else {
            let tmpDir = FileManager.default.temporaryDirectory
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let filename = "screenshot_\(formatter.string(from: Date())).png"
            outputPath = tmpDir.appendingPathComponent(filename).path
        }

        let startTime = Date()

        // 使用 ScreenCaptureKit — macOS 14+ 原生 API，自动触发权限弹窗
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw ScreenshotError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = true

        // SCScreenshotManager 不支持 async，用 Task 包装
        let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration,
                completionHandler: { image, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: ScreenshotError.permissionDenied)
                    }
                }
            )
        }

        // 写入 PNG 文件
        let url = URL(fileURLWithPath: outputPath)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            throw ScreenshotError.writeFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ScreenshotError.writeFailed
        }

        let elapsed = Date().timeIntervalSince(startTime)

        let fileSize: String
        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath),
           let size = attrs[.size] as? Int64 {
            fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            fileSize = "未知"
        }

        let width = cgImage.width
        let height = cgImage.height

        return """
        screenshot_captured: true
        file_path: \(outputPath)
        file_size: \(fileSize)
        resolution: \(width)x\(height)
        elapsed_seconds: \(String(format: "%.1f", elapsed))
        """
    }
}

enum ScreenshotError: LocalizedError {
    case noDisplayFound
    case permissionDenied
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "未找到可截图的显示器。"
        case .permissionDenied:
            return "截图权限被拒绝。请打开 系统设置 → 隐私与安全性 → 屏幕录制，允许本应用访问屏幕后重试。"
        case .writeFailed:
            return "截图文件写入失败，请检查磁盘空间和路径权限。"
        }
    }
}
#endif

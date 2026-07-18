//
//  DownloadFileTool.swift
//  CodeAgent
//
//  Created by xiaoyuan on 2026/6/30.
//

import AgentKit
import Foundation

// MARK: - DownloadFileTool

/// 通用文件下载工具 — 将任意 URL 资源下载到 workspace 的 downloads/ 目录。
///
/// 使用 iOS 原生 URLSession 下载任何类型的文件（视频、音频、图片、文档、压缩包等），
/// 保存到 App Documents/downloads/ 下，AI Agent 可通过文件系统工具看到和管理。
///
/// 注册方式：
/// ```swift
/// let registry = ToolRegistry()
/// await registry.register(DownloadFileTool())
/// ```
///
/// 输入参数：
/// - `url` (必填): 文件直链
/// - `fileName` (可选): 自定义保存文件名，默认从 URL / Content-Disposition 推断
/// - `overwrite` (可选): 文件已存在时是否覆盖，默认 true
struct DownloadFileTool: ClientTool {

    let name = "download_file"
    let description = "Download any file (image, video, audio, document, archive, etc.) to the workspace downloads/ directory"

    var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "url": .object([
                    "type": .string("string"),
                    "description": .string("Direct download URL of the file (e.g. https://example.com/video.mp4, https://example.com/image.png)")
                ]),
                "fileName": .object([
                    "type": .string("string"),
                    "description": .string("Optional custom file name including extension. If omitted, inferred from URL or Content-Disposition header.")
                ]),
                "overwrite": .object([
                    "type": .string("boolean"),
                    "description": .string("Overwrite if file already exists. Default: true"),
                    "default": .bool(true)
                ])
            ]),
            "required": .array([.string("url")])
        ])
    }

    func execute(args: JSONValue?) async throws -> String {
        // ========== 1. 解析参数 ==========
        guard let args else {
            throw ToolError.invalidArguments("No arguments provided. Required: url")
        }

        guard case .object(let dict) = args else {
            throw ToolError.invalidArguments("Arguments must be a JSON object")
        }

        // url（必填）
        guard let urlValue = dict["url"], case .string(let urlString) = urlValue else {
            throw ToolError.invalidArguments("Missing or invalid required parameter: url (must be a string)")
        }

        guard let url = URL(string: urlString), url.scheme != nil else {
            throw ToolError.invalidArguments("Invalid URL format: \(urlString)")
        }

        // fileName（可选）
        var customName: String?
        if let fileNameValue = dict["fileName"], case .string(let name) = fileNameValue {
            customName = name
        }

        // overwrite（可选，默认 true）
        var overwrite = true
        if let overwriteValue = dict["overwrite"], case .bool(let ov) = overwriteValue {
            overwrite = ov
        }

        // ========== 2. 确定保存路径 ==========
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsDir = documentsDir.appendingPathComponent("downloads", isDirectory: true)

        try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let fileName = try resolveFileName(
            customName: customName,
            from: url,
            downloadsDir: downloadsDir,
            fileManager: fileManager,
            overwrite: overwrite
        )

        let saveURL = downloadsDir.appendingPathComponent(fileName)

        // ========== 3. 下载文件 ==========
        print("📥 Downloading: \(urlString)")
        print("📂 Saving to: \(saveURL.path)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.downloadFailed("Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ToolError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }

        // ========== 4. 写入文件 ==========
        try data.write(to: saveURL, options: .atomic)

        let fileSize = Int64(data.count)

        // ========== 5. 构建返回结果 ==========
        let relativePath = "downloads/\(fileName)"
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeStr = formatter.string(fromByteCount: fileSize)

        let mimeType = httpResponse.mimeType ?? "unknown"

        return """
✅ Download complete!
   📂 Path: \(relativePath)
   📄 File: \(fileName)
   📏 Size: \(sizeStr) (\(fileSize) bytes)
   🏷 MIME: \(mimeType)
   📍 Absolute: \(saveURL.path)
"""
    }

    // MARK: - Helpers

    /// 解析最终文件名。
    /// 优先级：自定义名 > URL 最后路径 > 时间戳兜底。
    private func resolveFileName(
        customName: String?,
        from url: URL,
        downloadsDir: URL,
        fileManager: FileManager,
        overwrite: Bool
    ) throws -> String {
        // 自定义名
        if let custom = customName, !custom.isEmpty {
            if overwrite { return custom }
            let fileURL = downloadsDir.appendingPathComponent(custom)
            if !fileManager.fileExists(atPath: fileURL.path) { return custom }
            return try makeUnique(base: custom, dir: downloadsDir, fileManager: fileManager)
        }

        // 从 URL 推断
        let lastPath = url.lastPathComponent
        if !lastPath.isEmpty && lastPath != "/" {
            let decoded = lastPath.removingPercentEncoding ?? lastPath
            let cleanName = decoded.components(separatedBy: "?").first ?? decoded
            if overwrite { return cleanName }
            let fileURL = downloadsDir.appendingPathComponent(cleanName)
            if !fileManager.fileExists(atPath: fileURL.path) { return cleanName }
            return try makeUnique(base: cleanName, dir: downloadsDir, fileManager: fileManager)
        }

        // 兜底：时间戳
        let fallbackName = "download_\(ISO8601DateFormatter().string(from: Date()))"
        if overwrite { return fallbackName }
        let fileURL = downloadsDir.appendingPathComponent(fallbackName)
        if !fileManager.fileExists(atPath: fileURL.path) { return fallbackName }
        return try makeUnique(base: fallbackName, dir: downloadsDir, fileManager: fileManager)
    }

    /// 生成不重复的文件名：name → name_1, name_2, ...
    private func makeUnique(base: String, dir: URL, fileManager: FileManager) throws -> String {
        let ext = (base as NSString).pathExtension
        let body = (base as NSString).deletingPathExtension
        for i in 1...999 {
            let name = ext.isEmpty ? "\(body)_\(i)" : "\(body)_\(i).\(ext)"
            let fileURL = dir.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: fileURL.path) {
                return name
            }
        }
        let ts = Int(Date().timeIntervalSince1970)
        return ext.isEmpty ? "\(body)_\(ts)" : "\(body)_\(ts).\(ext)"
    }
}

// MARK: - Errors

enum ToolError: Error, LocalizedError {
    case invalidArguments(String)
    case downloadFailed(String)
    case fileWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let msg): return "Invalid arguments: \(msg)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .fileWriteFailed(let msg): return "File write failed: \(msg)"
        }
    }
}

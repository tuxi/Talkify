//
//  WorkspaceFileContentProvider.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

#if os(iOS)
import Foundation
import AgentKit
import FileViewerKit

// MARK: - Workspace File Node

/// 轻量 `FileNode` 实现，直接映射 `FileManager` 的文件系统条目。
private struct WorkspaceFileNode: FileViewerKit.FileNode {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?
    let modifiedAt: Date?
    var children: [WorkspaceFileNode]?

    init(url: URL, workspaceRoot: String) {
        let fullPath = url.path
        self.id = fullPath
        self.name = url.lastPathComponent
        self.path = fullPath.hasPrefix(workspaceRoot)
            ? String(fullPath.dropFirst(workspaceRoot.hasSuffix("/") ? workspaceRoot.count : workspaceRoot.count + 1))
            : fullPath
        self.isDirectory = url.hasDirectoryPath
        self.size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        self.modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        self.children = nil
    }
}

// MARK: - Workspace File Content Provider

/// 桥接层：将 `WorkspaceStore`（AgentKit）的数据适配到 FileViewerKit 和 AgentKit 的
/// `FileContentProvider` 协议。
///
/// 同时实现两个协议以消除类型歧义：
/// - `FileViewerKit.FileContentProvider` — FileTreeView / FilePreviewHost / WorkspaceBrowserView / FileChangeCard
/// - `AgentKit.FileContentProvider` — InspectorNavigationView
@MainActor
final class WorkspaceFileContentProvider {

    private let store: WorkspaceStore
    private let fileManager: FileManager

    init(store: WorkspaceStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    // MARK: - Workspace Path Resolution

    /// 从当前选中会话推断工作区根路径。
    /// 公开当前工作区根路径，供外部（如 deep link）使用。
    func currentWorkspaceRoot() -> String? { workspaceRoot }

    private var workspaceRoot: String? {
        if let path = store.selectedConversation?.workspacePath, !path.isEmpty {
            return path
        }
        if let first = store.recentWorkspaces.workspaces.first {
            return first.url.path
        }
        if let first = store.projects.projects.first {
            return first.url.path
        }
        return nil
    }

    private func resolveAbsolutePath(_ filePath: String) -> String {
        guard let root = workspaceRoot else { return filePath }
        if filePath.hasPrefix("/") { return filePath }
        let separator = root.hasSuffix("/") ? "" : "/"
        return root + separator + filePath
    }

    // MARK: - FileType Detection

    private enum DetectedType {
        case text, image, video, pdf, binary
    }

    private func detectType(_ path: String) -> DetectedType {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff":
            return .image
        case "mp4", "mov", "m4v", "avi", "mkv":
            return .video
        case "pdf":
            return .pdf
        case "swift", "m", "h", "c", "cpp", "mm", "kt", "java", "py", "rb", "go",
             "rs", "ts", "js", "json", "xml", "yaml", "yml", "plist", "xcconfig",
             "md", "txt", "csv", "html", "css", "sh", "zsh", "bash", "toml",
             "gradle", "podspec", "pbxproj", "entitlements", "storyboard",
             "xib", "strings", "gitignore", "lock", "resolved":
            return .text
        default:
            return .binary
        }
    }
}

// MARK: - FileViewerKit.FileContentProvider

extension WorkspaceFileContentProvider: FileViewerKit.FileContentProvider {

    func content(for filePath: String) async throws -> FileViewerKit.FileContent {
        let absPath = resolveAbsolutePath(filePath)
        guard fileManager.fileExists(atPath: absPath) else {
            throw FileViewerKit.FilePreviewError.fileNotFound(path: filePath)
        }

        let url = URL(fileURLWithPath: absPath)

        switch detectType(filePath) {
        case .text:
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                return .text(text)
            }
            return .binary(name: url.lastPathComponent, size: Int64(data.count))

        case .image:
            return .image(url)

        case .video:
            return .video(url)

        case .pdf:
            return .pdf(url)

        case .binary:
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return .binary(name: url.lastPathComponent, size: size)
        }
    }

    func changes(for filePath: String, baseRef: String?) async throws -> FileViewerKit.FileChange? {
        guard let root = workspaceRoot else { return nil }
        guard let gitReader = GitObjectReader(workspaceRoot: root) else { return nil }

        let absPath = resolveAbsolutePath(filePath)
        guard fileManager.fileExists(atPath: absPath) else { return nil }

        // Get file content at HEAD from git
        guard let oldContent = try? gitReader.contentAtHead(for: filePath) else { return nil }

        // Check if file is new (exists in working tree but not in HEAD)
        let currentData = try Data(contentsOf: URL(fileURLWithPath: absPath))
        guard let newContent = String(data: currentData, encoding: .utf8) else { return nil }

        // Determine status
        let status: FileViewerKit.ChangeStatus
        if oldContent == newContent {
            return nil // No changes
        }

        let fileExistsInGit = (try? gitReader.contentAtHead(for: filePath)) != nil
        if !fileExistsInGit {
            status = .added
        } else {
            status = .modified
        }

        // Compute diff hunks
        let hunks = LineDiffer.diff(old: oldContent, new: newContent)
        let fileHunks: [FileViewerKit.DiffHunk] = hunks.map { hunk in
            let lines: [FileViewerKit.DiffLine] = hunk.lines.map { kind in
                switch kind {
                case .unchanged(let t): return .unchanged(t)
                case .added(let t):     return .added(t)
                case .removed(let t):   return .removed(t)
                }
            }
            return FileViewerKit.DiffHunk(oldStart: hunk.oldStart, newStart: hunk.newStart, lines: lines)
        }

        let addedCount = hunks.flatMap(\.lines).filter {
            if case .added = $0 { return true }; return false
        }.count
        let removedCount = hunks.flatMap(\.lines).filter {
            if case .removed = $0 { return true }; return false
        }.count

        let summary = "\(addedCount) 行新增, \(removedCount) 行删除"

        return FileViewerKit.FileChange(
            filePath: filePath,
            status: status,
            summary: summary,
            hunks: fileHunks
        )
    }

    func children(of directoryPath: String) async throws -> [any FileViewerKit.FileNode] {
        let absPath = resolveAbsolutePath(directoryPath)
        let url = URL(fileURLWithPath: absPath)

        guard fileManager.fileExists(atPath: absPath) else {
            throw FileViewerKit.FilePreviewError.fileNotFound(path: directoryPath)
        }

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let root = workspaceRoot ?? absPath

        return contents
            .sorted { a, b in
                let aDir = a.hasDirectoryPath
                let bDir = b.hasDirectoryPath
                if aDir != bDir { return aDir }
                return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
            .map { WorkspaceFileNode(url: $0, workspaceRoot: root) }
    }

    func supportsPreview(for filePath: String) -> Bool {
        let ext = (filePath as NSString).pathExtension.lowercased()
        return ["swift", "m", "h", "c", "cpp", "mm", "kt", "java", "py", "rb",
                "go", "rs", "ts", "js", "json", "xml", "yaml", "yml", "md",
                "txt", "csv", "html", "css", "sh", "png", "jpg", "jpeg",
                "gif", "heic", "mp4", "mov", "pdf"].contains(ext)
    }
}

// MARK: - AgentKit.FileContentProvider

extension WorkspaceFileContentProvider: AgentKit.FileContentProvider {

    func content(for filePath: String) async throws -> String {
        let absPath = resolveAbsolutePath(filePath)
        guard fileManager.fileExists(atPath: absPath) else {
            throw FileViewerKit.FilePreviewError.fileNotFound(path: filePath)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: absPath))
        guard let text = String(data: data, encoding: .utf8) else {
            throw FileViewerKit.FilePreviewError.unsupportedType("Binary file: \(filePath)")
        }
        return text
    }

    func changes(for filePath: String, baseRef: String?) async throws -> AgentKit.DiffContent? {
        guard let root = workspaceRoot else { return nil }
        guard let gitReader = GitObjectReader(workspaceRoot: root) else { return nil }

        let absPath = resolveAbsolutePath(filePath)
        guard fileManager.fileExists(atPath: absPath) else { return nil }

        guard let oldContent = try? gitReader.contentAtHead(for: filePath) else { return nil }
        let currentData = try Data(contentsOf: URL(fileURLWithPath: absPath))
        guard let newContent = String(data: currentData, encoding: .utf8) else { return nil }

        guard oldContent != newContent else { return nil }

        let hunks = LineDiffer.diff(old: oldContent, new: newContent)
        let diffHunks: [AgentKit.DiffHunk] = hunks.map { hunk in
            let lines: [AgentKit.DiffLine] = hunk.lines.map { kind in
                switch kind {
                case .unchanged(let t): return .unchanged(t)
                case .added(let t):     return .added(t)
                case .removed(let t):   return .removed(t)
                }
            }
            let oldCount = lines.filter { if case .removed = $0 { true } else { false } }.count
            let newCount = lines.filter { if case .added = $0 { true } else { false } }.count
            return AgentKit.DiffHunk(
                id: "\(hunk.oldStart)-\(hunk.newStart)",
                oldStart: hunk.oldStart,
                oldCount: max(oldCount, 1),
                newStart: hunk.newStart,
                newCount: max(newCount, 1),
                lines: lines
            )
        }

        return AgentKit.DiffContent(original: oldContent, modified: newContent, hunks: diffHunks)
    }
}

// MARK: - WorkspaceItem Factory

extension WorkspaceFileContentProvider {

    /// 从 AgentKit 的 `Workspace` 构建 FileViewerKit 所需的 `WorkspaceItem` 列表。
    func buildWorkspaceItems() -> [FileViewerKit.WorkspaceItem] {
        var seen: Set<String> = []
        var items: [FileViewerKit.WorkspaceItem] = []

        for workspace in store.recentWorkspaces.workspaces + store.projects.projects {
            let path = workspace.url.path
            guard seen.insert(path).inserted else { continue }

            let conversations = store.listViewModel.conversations.filter {
                $0.workspaceGroupingID == "path:\(path)"
            }
            let fileCount = countFiles(in: path)

            items.append(FileViewerKit.WorkspaceItem(
                id: path,
                name: workspace.name,
                rootPath: path,
                conversationCount: conversations.count,
                fileCount: fileCount,
                uncommittedChanges: 0,
                lastActiveAt: workspace.branch != nil ? Date() : nil
            ))
        }

        return items
    }

    private func countFiles(in directoryPath: String) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: directoryPath),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator {
            if !url.hasDirectoryPath { count += 1 }
            if count > 1000 { break }
        }
        return count
    }
}

// MARK: - File Search

extension WorkspaceFileContentProvider {

    /// 在 workspace 根目录下递归搜索匹配的文件名。
    func searchFiles(matching query: String) -> [any FileViewerKit.FileNode] {
        guard let root = workspaceRoot else { return [] }
        let lowerQuery = query.lowercased()
        guard !lowerQuery.isEmpty else { return [] }

        let url = URL(fileURLWithPath: root)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [WorkspaceFileNode] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent.lowercased()
            if name.contains(lowerQuery) {
                results.append(WorkspaceFileNode(url: fileURL, workspaceRoot: root))
            }
            if results.count >= 30 { break }
        }
        return results
    }
}

// MARK: - Quick File List Helpers

extension WorkspaceFileContentProvider {

    /// 获取最近修改的文件（按修改时间倒序，最多 10 个）。
    func recentChangedFiles() -> [any FileViewerKit.FileNode] {
        guard let root = workspaceRoot else { return [] }
        let url = URL(fileURLWithPath: root)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(WorkspaceFileNode, Date)] = []
        for case let fileURL as URL in enumerator {
            guard !fileURL.hasDirectoryPath else { continue }
            if let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                files.append((WorkspaceFileNode(url: fileURL, workspaceRoot: root), modDate))
            }
            if files.count >= 100 { break }
        }

        return files
            .sorted { $0.1 > $1.1 }
            .prefix(10)
            .map { $0.0 as any FileViewerKit.FileNode }
    }
}
#endif

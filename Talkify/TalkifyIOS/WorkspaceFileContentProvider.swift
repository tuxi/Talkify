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
import CoreKit

private struct WorkspaceCanonicalTextChange {
    let original: String
    let modified: String
    let fileChange: FileViewerKit.FileChange
}

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
    private let workspaceContext: IOSWorkspaceContext
    private let fileManager: FileManager
    private let maximumDiffTextBytes = 2 * 1_024 * 1_024
    private let maximumDiffCells = 4_000_000

    init(
        store: WorkspaceStore,
        workspaceContext: IOSWorkspaceContext,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.workspaceContext = workspaceContext
        self.fileManager = fileManager
    }

    /// Legacy inspector bridge used by the split-view shell. The drawer path injects
    /// and retains its context explicitly; this fallback derives one from the store.
    convenience init(store: WorkspaceStore, fileManager: FileManager = .default) {
        self.init(
            store: store,
            workspaceContext: IOSWorkspaceContext(store: store),
            fileManager: fileManager
        )
    }

    // MARK: - Workspace Path Resolution

    /// 当前 Hub 工作区的实际文件根；Managed Worktree 会话优先使用其 checkout。
    /// 公开当前工作区根路径，供外部（如 deep link）使用。
    func currentWorkspaceRoot() -> String? { workspaceRoot }

    private var workspaceRoot: String? {
        if let conversation = store.selectedConversation,
           workspaceContext.contains(conversation),
           !conversation.workspacePath.isEmpty {
            let path = conversation.workspacePath
            return path
        }
        return workspaceContext.activeWorkspace?.url.path
    }

    private func resolveAbsolutePath(_ filePath: String) -> String {
        guard let root = workspaceRoot else { return filePath }
        if filePath.hasPrefix("/") { return filePath }
        let separator = root.hasSuffix("/") ? "" : "/"
        return root + separator + filePath
    }

    // MARK: - Workspace Content Import

    /// 将文件选择器返回的文件或文件夹 copy-in 到当前工作区根目录。
    /// 名称冲突时保留两份并追加序号，绝不覆盖工作区已有内容。
    func importItems(_ sourceURLs: [URL]) async throws {
        guard let workspaceRoot else {
            throw WorkspaceContentImportError.noActiveWorkspace
        }
        guard !sourceURLs.isEmpty else { return }

        let destinationRoot = URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            for sourceURL in sourceURLs {
                try Task.checkCancellation()
                let hasAccess = sourceURL.startAccessingSecurityScopedResource()
                defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }

                let destination = Self.uniqueImportDestination(
                    for: sourceURL,
                    in: destinationRoot,
                    fileManager: fileManager
                )
                try fileManager.copyItem(at: sourceURL, to: destination)
            }
        }.value
    }

    /// 将当前实际浏览根（主工作区或当前会话 Worktree）导出为 ZIP。
    func exportWorkspaceArchive() async throws -> URL {
        guard let workspaceRoot else {
            throw WorkspaceContentImportError.noActiveWorkspace
        }
        let displayName = workspaceContext.activeWorkspace?.name
            ?? URL(fileURLWithPath: workspaceRoot).lastPathComponent
        return try await WorkspaceArchiveExporter.export(
            workspaceURL: URL(fileURLWithPath: workspaceRoot, isDirectory: true),
            displayName: displayName
        )
    }

    nonisolated private static func uniqueImportDestination(
        for sourceURL: URL,
        in root: URL,
        fileManager: FileManager
    ) -> URL {
        let originalName = sourceURL.lastPathComponent.isEmpty ? "Imported" : sourceURL.lastPathComponent
        let initial = root.appendingPathComponent(originalName)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }

        let values = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        let fileExtension = isDirectory ? "" : sourceURL.pathExtension
        let baseName = isDirectory || fileExtension.isEmpty
            ? originalName
            : sourceURL.deletingPathExtension().lastPathComponent

        var suffix = 2
        while true {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(fileExtension)"
            let candidate = root.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    // MARK: - Shared Preview Content

    /// FileViewerKit owns live-file path validation, type detection and size limits.
    /// The legacy AgentKit protocol below only projects its typed result to text.
    private func localFileProvider() throws -> FileViewerKit.LocalFileContentProvider {
        guard let workspaceRoot else {
            throw WorkspaceContentImportError.noActiveWorkspace
        }
        return FileViewerKit.LocalFileContentProvider(
            rootURL: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        )
    }

    private func fileViewerContent(for filePath: String) async throws -> FileViewerKit.FileContent {
        try await localFileProvider().content(for: filePath)
    }

    /// Loads the two text snapshots once and projects them into FileViewerKit's
    /// canonical diff model. AgentKit compatibility is handled at one boundary below.
    private func canonicalTextChange(for filePath: String) throws -> WorkspaceCanonicalTextChange? {
        guard let root = workspaceRoot,
              let relativePath = workspaceRelativePath(filePath, root: root),
              let gitReader = GitObjectReader(workspaceRoot: root) else {
            return nil
        }

        let original = try gitReader.contentAtHead(for: relativePath)
        let workingURL = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let modified: String?
        if fileManager.fileExists(atPath: workingURL.path) {
            let values = try workingURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            let data = try Data(contentsOf: workingURL, options: [.mappedIfSafe])
            guard let text = String(data: data, encoding: .utf8) else {
                throw FileViewerKit.FilePreviewError.unsupportedType(
                    "Cannot diff non-UTF-8 file: \(relativePath)"
                )
            }
            modified = text
        } else {
            modified = nil
        }

        guard original != nil || modified != nil else { return nil }
        let oldText = original ?? ""
        let newText = modified ?? ""
        guard oldText != newText else { return nil }
        guard oldText.utf8.count <= maximumDiffTextBytes,
              newText.utf8.count <= maximumDiffTextBytes else {
            throw FileViewerKit.FilePreviewError.unsupportedType(
                "Diff text exceeds the \(Int64(maximumDiffTextBytes).formattedFileSize) preview limit"
            )
        }
        let oldLineCount = Self.lineCount(in: oldText)
        let newLineCount = Self.lineCount(in: newText)
        guard oldLineCount * newLineCount <= maximumDiffCells else {
            throw FileViewerKit.FilePreviewError.unsupportedType(
                "Diff is too large to calculate safely"
            )
        }

        let status: FileViewerKit.ChangeStatus
        switch (original, modified) {
        case (nil, .some): status = .added
        case (.some, nil): status = .deleted
        case (.some, .some): status = .modified
        case (nil, nil): return nil
        }

        let hunks = FileViewerKit.LineDiffBuilder.diff(old: oldText, new: newText)
        let addedCount = hunks.flatMap(\.lines).filter {
            if case .added = $0 { return true }
            return false
        }.count
        let removedCount = hunks.flatMap(\.lines).filter {
            if case .removed = $0 { return true }
            return false
        }.count

        return WorkspaceCanonicalTextChange(
            original: oldText,
            modified: newText,
            fileChange: FileViewerKit.FileChange(
                filePath: relativePath,
                status: status,
                summary: "\(addedCount) 行新增, \(removedCount) 行删除",
                hunks: hunks
            )
        )
    }

    private func workspaceRelativePath(_ filePath: String, root: String) -> String? {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let candidate = (filePath.hasPrefix("/")
            ? URL(fileURLWithPath: filePath)
            : rootURL.appendingPathComponent(filePath))
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }
        return String(candidate.path.dropFirst(rootPrefix.count))
    }

    nonisolated private static func lineCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
    }
}

private enum WorkspaceContentImportError: LocalizedError {
    case noActiveWorkspace

    var errorDescription: String? {
        switch self {
        case .noActiveWorkspace:
            return TalkifyLocalized.string("import.select_workspace_first")
        }
    }
}

// MARK: - FileViewerKit.FileContentProvider

extension WorkspaceFileContentProvider: FileViewerKit.FileContentProvider {

    func content(for filePath: String) async throws -> FileViewerKit.FileContent {
        try await fileViewerContent(for: filePath)
    }

    func changes(for filePath: String, baseRef: String?) async throws -> FileViewerKit.FileChange? {
        try canonicalTextChange(for: filePath)?.fileChange
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
//            options: [.skipsHiddenFiles]
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
        FileViewerKit.FileTypeDetector.supportsPreview(for: filePath)
    }

    func textChunk(
        for filePath: String,
        offset: Int64,
        length: Int
    ) async throws -> FileViewerKit.TextFileChunk? {
        try await localFileProvider().textChunk(
            for: filePath,
            offset: offset,
            length: length
        )
    }
}

// MARK: - AgentKit.FileContentProvider

extension WorkspaceFileContentProvider: AgentKit.FileContentProvider {

    func content(for filePath: String) async throws -> String {
        switch try await fileViewerContent(for: filePath) {
        case .text(let text):
            return text
        case .oversizedText(_, let size, let limit):
            throw FileViewerKit.FilePreviewError.unsupportedType(
                "Text file is \(size.formattedFileSize); preview limit is \(limit.formattedFileSize)"
            )
        case .image, .video, .pdf, .binary:
            throw FileViewerKit.FilePreviewError.unsupportedType("Non-text file: \(filePath)")
        }
    }

    func changes(for filePath: String, baseRef: String?) async throws -> AgentKit.DiffContent? {
        guard let change = try canonicalTextChange(for: filePath) else { return nil }
        return AgentKitDiffCompatibilityAdapter.content(
            original: change.original,
            modified: change.modified,
            hunks: change.fileChange.hunks
        )
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

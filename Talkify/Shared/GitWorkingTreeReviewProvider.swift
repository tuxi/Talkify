#if os(macOS)
import Foundation
import CryptoKit
import FileViewerKit

/// Git owns the comparison. Working bytes are captured once; per-file diff and
/// omitted context always refer to that immutable observation.
final class GitWorkingTreeReviewProvider: FileReviewSnapshotProvider, FileSystemRevealing, @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var snapshots: [String: Captured] = [:]
    private var snapshotOrder: [String] = []
    private var legacySnapshotID: String?
    private let maximumTextBytes = 2 * 1024 * 1024
    var supportsUnchangedLineLoading: Bool { true }
    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL; self.fileManager = fileManager
    }
    private struct Entry: Sendable { let path: String; let previous: String?; let x: String; let y: String }
    private struct Blob: Sendable { let oid: String; let mode: String; let size: Int }
    private struct Record: Sendable { let file: ReviewFile; let bytes: Data?; let old: Blob? }
    private struct Captured: Sendable { let snapshot: FileReviewSnapshot; let records: [String: Record] }
    /// File browsing needs only porcelain status, never full diff construction.
    func workingTreeStatuses() async throws -> [String: ChangeStatus] {
        try await background { [self] in
            guard fileManager.fileExists(atPath: rootURL.appendingPathComponent(".git").path) else { return [:] }
            let data = try Self.runGit(["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: rootURL)
            let records = data.split(separator: 0)
            var result: [String: ChangeStatus] = [:]; var index = 0
            while index < records.count {
                let record = records[index]; index += 1
                guard record.count >= 4, let path = String(bytes: record.dropFirst(3), encoding: .utf8) else { continue }
                let flags = String(decoding: record.prefix(2), as: UTF8.self)
                if flags.contains("R") || flags.contains("C") { index += 1 }
                let status: ChangeStatus = flags.contains("D") ? .deleted : (flags.contains("?") || flags.contains("A")) ? .added : .modified
                result[path] = status
                var parent = (path as NSString).deletingLastPathComponent
                while !parent.isEmpty && parent != "." {
                    result[parent] = result[parent].map { $0 == status ? status : .modified } ?? status
                    parent = (parent as NSString).deletingLastPathComponent
                }
            }
            return result
        }
    }


    func fileRevealLocation(for path: String) async throws -> FileRevealLocation {
        try await background { [rootURL] in
            try LocalFileRevealResolver.resolve(path: path, rootURL: rootURL)
        }
    }
    func reviewSnapshot() async throws -> FileReviewSnapshot {
        try await background { [self] in
            let captured = try capture()
            lock.withLock {
                snapshots[captured.snapshot.id] = captured
                snapshotOrder.removeAll { $0 == captured.snapshot.id }; snapshotOrder.append(captured.snapshot.id)
                while snapshotOrder.count > 3 { snapshots[snapshotOrder.removeFirst()] = nil }
            }
            return captured.snapshot
        }
    }
    func reviewObservation() async throws -> String {
        try await background { [self] in try observation() }
    }
    func reviewChange(path: String, snapshotID: String) async throws -> FileChange {
        try await background { [self] in
            guard let record = lock.withLock({ snapshots[snapshotID]?.records[path] }) else { throw FileReviewProviderError.staleSnapshot }
            return try makeChange(record)
        }
    }
    func reviewContext(path: String, snapshotID: String, startLine: Int, count: Int) async throws -> [String] {
        try await background { [self] in
            guard startLine > 0, count > 0, count <= 200 else { throw FileReviewProviderError.invalidLineRange }
            guard let record = lock.withLock({ snapshots[snapshotID]?.records[path] }) else { throw FileReviewProviderError.staleSnapshot }
            let data: Data
            if let bytes = record.bytes { data = bytes }
            else if record.file.status == .deleted { data = try oldBytes(record.old) }
            else { throw FileReviewProviderError.staleSnapshot }
            guard let text = String(data: data, encoding: .utf8) else { throw FileReviewProviderError.staleSnapshot }
            let lines = Self.lines(text)
            let lower = startLine - 1
            guard lower <= lines.count, count <= lines.count - lower else { throw FileReviewProviderError.invalidLineRange }
            return Array(lines[lower..<(lower + count)])
        }
    }
    func workingTreeChanges() async throws -> [FileChange] {
        let snapshot = try await reviewSnapshot()
        lock.withLock { legacySnapshotID = snapshot.id }
        var values: [FileChange] = []
        for file in snapshot.files { values.append(try await reviewChange(path: file.path, snapshotID: snapshot.id)) }
        return values
    }
    func unchangedLines(for filePath: String, startingAt lineNumber: Int, count: Int) async throws -> [String] {
        guard let id = lock.withLock({ legacySnapshotID }) else { throw FileReviewProviderError.staleSnapshot }
        return try await reviewContext(path: filePath, snapshotID: id, startLine: lineNumber, count: count)
    }
    private func background<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .utility) { try operation() }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func observation() throws -> String {
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &directory), directory.boolValue else { throw ReviewProviderError.message("工作目录不存在或不可读取。") }
        guard fileManager.fileExists(atPath: rootURL.appendingPathComponent(".git").path) else { return "not-git-root" }
        let status = try Self.runGit(["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: rootURL)
        let head = try Self.runGit(["rev-parse", "--verify", "HEAD"], at: rootURL, accepted: [0, 128])
        let branch = try Self.runGit(["symbolic-ref", "--quiet", "--short", "HEAD"], at: rootURL, accepted: [0, 1])
        var result = Data(head); result.append(branch); result.append(status)
        for entry in try Self.parseStatus(status) {
            let path = rootURL.appendingPathComponent(entry.path).path
            if let attributes = try? fileManager.attributesOfItem(atPath: path) {
                result.append(Data("\(attributes[.size] ?? "")|\(attributes[.modificationDate] as? Date ?? .distantPast)|\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(attributes[.systemFileNumber] ?? "")|\(attributes[.posixPermissions] ?? "")".utf8))
            }
        }
        return Self.hash(result)
    }
    private func capture() throws -> Captured {
        let gitMarker = rootURL.appendingPathComponent(".git").path
        guard fileManager.fileExists(atPath: gitMarker) else {
            // A nested directory is not a separate repository and must not quietly
            // project paths relative to the wrong root.
            do {
                _ = try Self.runGit(["rev-parse", "--show-toplevel"], at: rootURL)
            } catch {
                if error.localizedDescription.contains("not a git repository") {
                    return Captured(snapshot: .init(id: "not-git", baselineRevision: "", state: .notGit, files: []), records: [:])
                }
                throw error
            }
            throw ReviewProviderError.message("请选择 Git 仓库根目录查看变更。")
        }
        let before = try observation()
        let headData = try Self.runGit(["rev-parse", "--verify", "HEAD"], at: rootURL, accepted: [0, 128])
        let headText = String(decoding: headData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // Failed rev-parse writes no SHA to stdout.
        let head = headText.count == 40 || headText.count == 64 ? headText : nil
        let branchData = try Self.runGit(["symbolic-ref", "--quiet", "--short", "HEAD"], at: rootURL, accepted: [0, 1])
        let branch = String(decoding: branchData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if head == nil && branch.isEmpty { throw ReviewProviderError.message("无法确定仓库 HEAD。") }
        let status = try Self.runGit(["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: rootURL)
        let entries = try Self.parseStatus(status)
        guard entries.count <= 2000 else { throw ReviewProviderError.message("变更文件超过 2000 个，请缩小工作区或先处理生成文件。") }
        let treePaths = Array(Set(entries.map { $0.previous ?? $0.path })).sorted()
        let tree = head == nil || treePaths.isEmpty ? [:] : try Self.parseTree(Self.runGit(["ls-tree", "-r", "-z", "--long", head!, "--"] + treePaths, at: rootURL))
        let stats = head == nil ? [:] : try Self.parseNumstat(Self.runGit(["diff", "--numstat", "-z", "--no-ext-diff", "--no-textconv", "--find-renames", head!, "--"], at: rootURL))
        var records: [String: Record] = [:]; var budget = 24 * 1024 * 1024
        for entry in entries {
            try Task.checkCancellation()
            let old = tree[entry.previous ?? entry.path]
            let url = rootURL.appendingPathComponent(entry.path).standardizedFileURL
            guard url.path.hasPrefix(rootURL.path + "/") else { throw ReviewProviderError.message("变更路径超出当前仓库。") }
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let type = attributes?[.type] as? FileAttributeType
            var bytes: Data?; var note: String?; var digest = "deleted"
            let conflict = entry.x == "U" || entry.y == "U" || ["AA", "DD"].contains(entry.x + entry.y)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            let outside = resolved.path != rootURL.path && !resolved.path.hasPrefix(rootURL.path + "/")
            if type != .typeSymbolicLink && outside {
                note = "路径通过符号链接离开仓库，未读取目标。"; digest = "outside"
            } else if type == .typeSymbolicLink {
                note = "符号链接变化；不读取链接目标。"
                bytes = try fileManager.destinationOfSymbolicLink(atPath: url.path).data(using: .utf8)
                digest = Self.hash(bytes ?? Data())
            } else if old?.mode == "160000" || type == .typeDirectory {
                note = "子模块或目录元数据变化，没有普通文件 diff。"; digest = before
            } else if type == .typeRegular {
                if size <= maximumTextBytes && size <= budget {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    bytes = try handle.read(upToCount: maximumTextBytes + 1) ?? Data()
                    guard bytes!.count <= maximumTextBytes, url.resolvingSymlinksInPath().standardizedFileURL == resolved else { throw ReviewProviderError.message("文件在读取时发生变化，请刷新。") }
                    budget -= bytes!.count; digest = Self.hash(bytes!)
                    if bytes!.contains(0) || String(data: bytes!, encoding: .utf8) == nil { note = "二进制或非 UTF-8 文件，没有文本 diff。" }
                } else {
                    note = size > maximumTextBytes ? "文件超过 2 MB，暂不展开文本 diff。" : "本次快照达到内容预算，暂不展开此文件。"
                    // Stream a digest: content identity must not rely on size/mtime.
                    digest = try Self.fileHash(url)
                }
            } else if attributes != nil { note = "此文件类型暂不支持预览。"; digest = before }
            else if entry.y != "D" && entry.x != "D" { throw ReviewProviderError.message("无法读取 \(entry.path)，请检查权限后刷新。") }
            if old == nil && attributes == nil { note = "暂存区与工作区状态不同，最终内容与 HEAD 无文本差异。" }
            if conflict { note = "文件存在合并冲突，请先解决冲突。" }
            if old?.mode == "120000" { note = "符号链接变化；不读取链接目标。" }
            if (old?.size ?? 0) > maximumTextBytes { note = "基线文件超过 2 MB，暂不展开文本 diff。" }
            let status: ChangeStatus = old == nil ? .added : (attributes == nil ? .deleted : .modified)
            let revision = Self.hash(Data("\(old?.oid ?? "empty")|\(old?.mode ?? "")|\(digest)|\(attributes?[.posixPermissions] ?? "")|\(conflict)|\(entry.previous ?? "")".utf8))
            let numbers = stats[entry.path]
            let untrackedCount = old == nil && note == nil ? bytes.flatMap { String(data: $0, encoding: .utf8) }.map { Self.lines($0).count } : nil
            let file = ReviewFile(path: entry.path, previousPath: entry.previous, status: status, indexStatus: entry.x, worktreeStatus: entry.y, revision: revision,
                                  added: conflict || old?.mode == "160000" ? nil : (numbers?.0 ?? untrackedCount), removed: conflict || old?.mode == "160000" ? nil : (numbers?.1 ?? (untrackedCount == nil ? nil : 0)), note: note)
            records[entry.path] = Record(file: file, bytes: bytes, old: old)
        }
        guard try observation() == before else { throw ReviewProviderError.message("工作区正在变化，请稍后刷新。当前审阅内容已保留。") }
        let files = records.values.map(\.file).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let baseline = head ?? "empty-tree"
        let id = Self.hash(Data((baseline + files.map { $0.path + "|" + $0.revision + "|" + $0.indexStatus + $0.worktreeStatus + "|" + ($0.note ?? "") }.joined(separator: "\n")).utf8))
        return Captured(snapshot: .init(id: id, baselineRevision: baseline, branch: branch.isEmpty ? nil : branch, state: head == nil ? .unborn : .ready, files: files), records: records)
    }
    private func oldBytes(_ blob: Blob?) throws -> Data {
        guard let blob else { return Data() }
        guard blob.size <= maximumTextBytes else { throw ReviewProviderError.message("基线文件过大。") }
        return try Self.runGit(["cat-file", "blob", blob.oid], at: rootURL)
    }
    private func makeChange(_ record: Record) throws -> FileChange {
        let file = record.file
        if let note = file.note { return .init(filePath: file.path, status: file.status, summary: note, hunks: []) }
        let old = try oldBytes(record.old), new = record.bytes ?? Data()
        guard !old.contains(0), String(data: old, encoding: .utf8) != nil else { return .init(filePath: file.path, status: file.status, summary: "基线为二进制或非 UTF-8 文件。", hunks: []) }
        let temp = fileManager.temporaryDirectory.appendingPathComponent("TalkifyReview-" + UUID().uuidString)
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temp) }
        let before = temp.appendingPathComponent("before"), after = temp.appendingPathComponent("after")
        try old.write(to: before); try new.write(to: after)
        let patch = try Self.runGit(["diff", "--no-index", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=3", "--", before.path, after.path], at: rootURL, accepted: [0, 1])
        guard patch.count <= 1024 * 1024 else { return .init(filePath: file.path, status: file.status, summary: "差异超过展示预算，请在 Files 中查看。", hunks: []) }
        let hunks = try Self.parsePatch(patch)
        guard hunks.reduce(0, { $0 + $1.lines.count }) <= 5000 else { return .init(filePath: file.path, status: file.status, summary: "差异超过 5000 行，暂不展开。", hunks: []) }
        return .init(filePath: file.path, status: file.status, summary: hunks.isEmpty ? (file.status == .added ? "新建空文件。" : file.status == .deleted ? "空文件已删除。" : "文件路径或属性变化，无文本差异。") : "", hunks: hunks)
    }
    private static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var result = text.components(separatedBy: "\n"); if result.last == "" { result.removeLast() }; return result
    }
    private static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private static func fileHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 65536), !data.isEmpty { try Task.checkCancellation(); digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func parseStatus(_ data: Data) throws -> [Entry] {
        let records = data.split(separator: 0); var values: [Entry] = []; var index = 0
        while index < records.count {
            let record = records[index]; index += 1
            guard record.count >= 4, let path = String(bytes: record.dropFirst(3), encoding: .utf8) else { throw ReviewProviderError.message("Git 文件名无法读取。") }
            let flags = Array(record.prefix(2)); var previous: String?
            if flags.contains(82) || flags.contains(67) {
                guard index < records.count else { throw ReviewProviderError.message("Git 重命名记录不完整。") }
                previous = String(bytes: records[index], encoding: .utf8); index += 1
            }
            values.append(Entry(path: path, previous: previous, x: String(UnicodeScalar(flags[0])), y: String(UnicodeScalar(flags[1]))))
        }
        return values
    }
    private static func parseTree(_ data: Data) throws -> [String: Blob] {
        var values: [String: Blob] = [:]
        for row in data.split(separator: 0) {
            guard let tab = row.firstIndex(of: 9), let path = String(bytes: row[row.index(after: tab)...], encoding: .utf8) else { throw ReviewProviderError.message("Git 基线文件名无法读取。") }
            let fields = String(decoding: row[..<tab], as: UTF8.self).split(whereSeparator: { $0 == " " })
            guard fields.count == 4 else { throw ReviewProviderError.message("Git 基线记录无法读取。") }
            values[path] = Blob(oid: String(fields[2]), mode: String(fields[0]), size: Int(fields[3]) ?? 0)
        }
        return values
    }
    private static func parseNumstat(_ data: Data) throws -> [String: (Int?, Int?)] {
        let rows = data.split(separator: 0, omittingEmptySubsequences: false); var index = 0; var values: [String: (Int?, Int?)] = [:]
        while index < rows.count {
            let row = rows[index]; index += 1; if row.isEmpty { continue }
            let fields = row.split(separator: 9, maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { throw ReviewProviderError.message("Git 行数统计无法读取。") }
            var path = String(decoding: fields[2], as: UTF8.self)
            if path.isEmpty {
                guard index + 1 < rows.count else { throw ReviewProviderError.message("Git 重命名统计不完整。") }
                path = String(decoding: rows[index + 1], as: UTF8.self); index += 2
            }
            values[path] = (Int(String(decoding: fields[0], as: UTF8.self)), Int(String(decoding: fields[1], as: UTF8.self)))
        }
        return values
    }
    static func parsePatch(_ data: Data) throws -> [DiffHunk] {
        guard let text = String(data: data, encoding: .utf8) else { throw ReviewProviderError.message("差异不是 UTF-8 文本。") }
        let regex = try NSRegularExpression(pattern: #"^@@ -([0-9]+)(?:,[0-9]+)? \+([0-9]+)(?:,[0-9]+)? @@"#)
        var hunks: [DiffHunk] = []; var start: (Int, Int)?; var lines: [DiffLine] = []
        for line in text.components(separatedBy: "\n") {
            if let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let start { hunks.append(.init(oldStart: start.0, newStart: start.1, lines: lines)) }
                let ns = line as NSString; start = (Int(ns.substring(with: match.range(at: 1)))!, Int(ns.substring(with: match.range(at: 2)))!); lines = []
            } else if start != nil {
                if line.hasPrefix("+") { lines.append(.added(String(line.dropFirst()))) }
                else if line.hasPrefix("-") { lines.append(.removed(String(line.dropFirst()))) }
                else if line.hasPrefix(" ") { lines.append(.unchanged(String(line.dropFirst()))) }
            }
        }
        if let start { hunks.append(.init(oldStart: start.0, newStart: start.1, lines: lines)) }
        return hunks
    }
    private static func runGit(_ arguments: [String], at rootURL: URL, accepted: Set<Int32> = [0]) throws -> Data {
        let process = Process()
        // Regular temporary files avoid stdout/stderr pipe deadlocks and are
        // deleted immediately after each bounded read-only command.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("TalkifyGit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let out = temp.appendingPathComponent("out"), err = temp.appendingPathComponent("err")
        FileManager.default.createFile(atPath: out.path, contents: nil); FileManager.default.createFile(atPath: err.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: out), errHandle = try FileHandle(forWritingTo: err)
        defer { try? outHandle.close(); try? errHandle.close() }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--literal-pathspecs", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", "-C", rootURL.path] + arguments
        process.standardInput = FileHandle.nullDevice; process.standardOutput = outHandle; process.standardError = errHandle
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C", "GIT_OPTIONAL_LOCKS": "0"]) { _, new in new }
        try Task.checkCancellation(); try process.run()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning {
            if Task.isCancelled { process.terminate(); process.waitUntilExit(); throw CancellationError() }
            if Date() > deadline { process.terminate(); process.waitUntilExit(); throw ReviewProviderError.message("Git 读取超时，请重试。") }
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        let size = try out.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 32 * 1024 * 1024 else { throw ReviewProviderError.message("Git 输出超过 32 MB，请缩小范围。") }
        guard accepted.contains(process.terminationStatus) else {
            let detail = String(decoding: (try? Data(contentsOf: err))?.prefix(4096) ?? Data(), as: UTF8.self)
            throw ReviewProviderError.message("无法读取 Git 变更：" + detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Data(contentsOf: out)
    }
}
private enum ReviewProviderError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}
#endif

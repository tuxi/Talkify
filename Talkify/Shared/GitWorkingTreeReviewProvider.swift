#if os(macOS)
import Foundation
import FileViewerKit

/// Read-only projection of a local Git working tree for the Inspector review tab.
final class GitWorkingTreeReviewProvider: FileReviewProvider, @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager
    private let maximumTextBytes = 2 * 1_024 * 1_024
    private let maximumDiffCells = 4_000_000

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        self.fileManager = fileManager
    }

    func workingTreeChanges() async throws -> [FileChange] {
        let statusData = try Self.runGit(
            ["status", "--porcelain=v1", "-z", "--untracked-files=all"],
            at: rootURL
        )
        let entries = Self.parseStatus(statusData)
        var changes: [FileChange] = []
        changes.reserveCapacity(entries.count)
        for entry in entries {
            try Task.checkCancellation()
            if let change = try Self.makeChange(
                entry,
                rootURL: rootURL,
                fileManager: fileManager,
                maximumTextBytes: maximumTextBytes,
                maximumDiffCells: maximumDiffCells
            ) {
                changes.append(change)
            }
        }
        return changes
    }

    private struct StatusEntry: Sendable {
        let path: String
    }

    private static func parseStatus(_ data: Data) -> [StatusEntry] {
        let records = data.split(separator: 0, omittingEmptySubsequences: true)
        var result: [StatusEntry] = []
        var index = 0

        while index < records.count {
            let record = records[index]
            guard record.count >= 4 else {
                index += 1
                continue
            }

            let x = record[record.startIndex]
            let y = record[record.index(after: record.startIndex)]
            let pathBytes = record.dropFirst(3)
            index += 1
            // In porcelain -z output, rename/copy records are followed by the old path.
            if x == 82 || x == 67 || y == 82 || y == 67 { // R / C
                if let path = String(bytes: pathBytes, encoding: .utf8) {
                    result.append(StatusEntry(path: path))
                }
                if (x == 82 || y == 82), index < records.count,
                   let oldPath = String(bytes: records[index], encoding: .utf8) {
                    result.append(StatusEntry(path: oldPath))
                }
                index += 1
            } else if let path = String(bytes: pathBytes, encoding: .utf8) {
                result.append(StatusEntry(path: path))
            }
        }
        return result
    }

    private static func makeChange(
        _ entry: StatusEntry,
        rootURL: URL,
        fileManager: FileManager,
        maximumTextBytes: Int,
        maximumDiffCells: Int
    ) throws -> FileChange? {
        let headData = try? runGit(["show", "HEAD:\(entry.path)"], at: rootURL)
        let workingData = try readWorkingData(
            at: entry.path,
            rootURL: rootURL,
            fileManager: fileManager
        )
        guard headData != nil || workingData != nil else { return nil }

        let status: ChangeStatus
        switch (headData, workingData) {
        case (nil, .some): status = .added
        case (.some, nil): status = .deleted
        case (.some, .some): status = .modified
        case (nil, nil): return nil
        }
        let oldData = headData ?? Data()
        let newData = workingData ?? Data()

        guard oldData.count <= maximumTextBytes,
              newData.count <= maximumTextBytes,
              !oldData.contains(0),
              !newData.contains(0),
              let oldText = String(data: oldData, encoding: .utf8),
              let newText = String(data: newData, encoding: .utf8) else {
            return FileChange(
                filePath: entry.path,
                status: status,
                summary: "Binary or large-file change",
                hunks: []
            )
        }

        let oldLineCount = oldText.isEmpty ? 0 : oldText.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        let newLineCount = newText.isEmpty ? 0 : newText.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        guard oldLineCount * newLineCount <= maximumDiffCells else {
            return FileChange(
                filePath: entry.path,
                status: status,
                summary: "Diff is too large to render",
                hunks: []
            )
        }

        let hunks = LineDiffBuilder.diff(old: oldText, new: newText)
        let added = hunks.flatMap(\.lines).filter { if case .added = $0 { true } else { false } }.count
        let removed = hunks.flatMap(\.lines).filter { if case .removed = $0 { true } else { false } }.count
        return FileChange(
            filePath: entry.path,
            status: status,
            summary: "+\(added) −\(removed)",
            hunks: hunks
        )
    }

    private static func readWorkingData(
        at path: String,
        rootURL: URL,
        fileManager: FileManager
    ) throws -> Data? {
        let unresolvedURL = rootURL.appendingPathComponent(path).standardizedFileURL
        guard fileManager.fileExists(atPath: unresolvedURL.path) else { return nil }
        let fileURL = unresolvedURL.resolvingSymlinksInPath().standardizedFileURL
        guard isInside(fileURL, rootURL: rootURL) else { return nil }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { return nil }
        return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    }

    private static func isInside(_ candidate: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        return candidate.path == rootURL.path || candidate.path.hasPrefix(rootPath)
    }

    private static func runGit(_ arguments: [String], at rootURL: URL) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootURL.path] + arguments
        process.standardOutput = output
        process.standardError = error
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }

        do {
            try process.run()
        } catch {
            throw ReviewProviderError.cannotLaunchGit(error.localizedDescription)
        }

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ReviewProviderError.gitFailed(message?.isEmpty == false ? message! : "git exited with status \(process.terminationStatus)")
        }
        return outputData
    }
}

private enum ReviewProviderError: LocalizedError {
    case cannotLaunchGit(String)
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotLaunchGit(let reason): "Unable to launch Git: \(reason)"
        case .gitFailed(let reason): "Unable to read working tree: \(reason)"
        }
    }
}
#endif

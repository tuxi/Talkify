//
//  GitObjectReader.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import Foundation
import Compression

// MARK: - Git Object Reader

/// Reads git objects directly from `.git/objects/` without shelling out to `git`.
/// Used to retrieve file content at HEAD for diff computation on iOS (where `Process` is unavailable).
final class GitObjectReader {

    private let gitDir: URL
    private let fileManager: FileManager

    init?(workspaceRoot: String, fileManager: FileManager = .default) {
        let dotGit: URL
        let rootURL = URL(fileURLWithPath: workspaceRoot)
        let candidate = rootURL.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            dotGit = candidate
        } else {
            // Check for .git file (worktree)
            if let content = try? String(contentsOf: candidate, encoding: .utf8),
               content.hasPrefix("gitdir:") {
                let gitDirPath = content
                    .dropFirst("gitdir:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                dotGit = URL(fileURLWithPath: gitDirPath, relativeTo: rootURL).standardizedFileURL
            } else {
                return nil
            }
        }
        self.gitDir = dotGit
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Returns the file content as stored in HEAD.
    func contentAtHead(for filePath: String) throws -> String? {
        guard let headSHA = try resolveHead() else { return nil }
        let commit = try readCommit(sha: headSHA)
        guard let treeSHA = commit.tree else { return nil }
        guard let blobSHA = try findBlob(inTree: treeSHA, for: filePath) else { return nil }
        let data = try readObject(sha: blobSHA)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    // MARK: - Ref Resolution

    private func resolveHead() throws -> String? {
        let headURL = gitDir.appendingPathComponent("HEAD")
        let raw = try String(contentsOf: headURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("ref:") {
            let ref = raw.dropFirst("ref:".count).trimmingCharacters(in: .whitespaces)
            let refURL = gitDir.appendingPathComponent(ref)
            guard fileManager.fileExists(atPath: refURL.path) else { return nil }
            return try String(contentsOf: refURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Detached HEAD: raw is already the commit SHA
        return raw.isEmpty ? nil : raw
    }

    // MARK: - Object Reading

    private func objectPath(sha: String) -> URL {
        let prefix = String(sha.prefix(2))
        let suffix = String(sha.dropFirst(2))
        return gitDir.appendingPathComponent("objects/\(prefix)/\(suffix)")
    }

    private func readObject(sha: String) throws -> Data {
        let url = objectPath(sha: sha)
        let compressed = try Data(contentsOf: url)
        return try decompress(compressed)
    }

    // MARK: - Commit Parsing

    private struct ParsedCommit {
        let tree: String?
    }

    private func readCommit(sha: String) throws -> ParsedCommit {
        let data = try readObject(sha: sha)
        guard let text = String(data: data, encoding: .utf8) else { return ParsedCommit(tree: nil) }
        for line in text.split(separator: "\n") {
            if line.hasPrefix("tree ") {
                return ParsedCommit(tree: String(line.dropFirst(5)))
            }
        }
        return ParsedCommit(tree: nil)
    }

    // MARK: - Tree Traversal

    private func findBlob(inTree treeSHA: String, for targetPath: String) throws -> String? {
        let data = try readObject(sha: treeSHA)
        var offset = 0
        let bytes = [UInt8](data)
        let components = targetPath.split(separator: "/").map(String.init)

        return try findInTree(bytes: bytes, offset: &offset, components: components, depth: 0)
    }

    private func findInTree(
        bytes: [UInt8],
        offset: inout Int,
        components: [String],
        depth: Int
    ) throws -> String? {
        guard depth < components.count else { return nil }
        let target = components[depth]

        while offset < bytes.count {
            // Read null-terminated "<mode> <name>"
            let start = offset
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            guard offset < bytes.count else { break }
            let entryStr = String(bytes: bytes[start..<offset], encoding: .utf8) ?? ""
            offset += 1 // skip null

            // Read 20-byte SHA
            guard offset + 20 <= bytes.count else { break }
            let shaBytes = bytes[offset..<offset + 20]
            offset += 20
            let sha = shaBytes.map { String(format: "%02x", $0) }.joined()

            // Parse mode and name
            let parts = entryStr.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let mode = String(parts[0])
            let name = String(parts[1])

            let isDir = mode.hasPrefix("4") // 40000 = tree
            if name == target {
                if depth == components.count - 1 {
                    // Found target: if it's a file, return blob SHA
                    return isDir ? nil : sha
                } else if isDir {
                    // Descend into directory
                    return try findInTree(bytes: bytes, offset: &offset, components: components, depth: depth + 1)
                }
            }
            // Continue to next entry
        }
        return nil
    }

    // MARK: - Decompression

    private func decompress(_ data: Data) throws -> Data {
        // Strip the "blob <size>\0" or "tree <size>\0" or "commit <size>\0" header
        // The header ends at the first null byte
        guard let nullIndex = data.firstIndex(of: 0) else {
            throw GitReaderError.invalidObject
        }
        let compressed = Data(data[(nullIndex + 1)...])

        var result = Data()
        let bufferSize = 32768
        var sourceBuffer = [UInt8](compressed)
        var destinationBuffer = [UInt8](repeating: 0, count: bufferSize)

        let status = compression_decode_buffer(
            &destinationBuffer, bufferSize,
            &sourceBuffer, sourceBuffer.count,
            nil,
            COMPRESSION_ZLIB
        )

        guard status > 0 else {
            throw GitReaderError.decompressionFailed
        }

        result.append(contentsOf: destinationBuffer[0..<status])

        // Continue if there's more data after the initial chunk header
        if status < bufferSize || result.count > 0 {
            return result
        }

        throw GitReaderError.decompressionFailed
    }

    enum GitReaderError: Error {
        case invalidObject
        case decompressionFailed
    }
}

// MARK: - Simple Line Diff

/// A minimal line-based diff generator.
/// Produces hunks suitable for `FileViewerKit.DiffHunk` and `AgentKit.DiffHunk`.
enum LineDiffer {

    struct Hunk {
        let oldStart: Int
        let newStart: Int
        let lines: [DiffLineKind]
    }

    enum DiffLineKind {
        case unchanged(String)
        case added(String)
        case removed(String)
    }

    /// Compute line-level diff between old and new text.
    static func diff(old: String, new: String, contextLines: Int = 3) -> [Hunk] {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let edits = computeEdits(old: oldLines, new: newLines)
        guard !edits.isEmpty else { return [] }

        return buildHunks(oldLines: oldLines, newLines: newLines, edits: edits, context: contextLines)
    }

    // MARK: - Edit Computation (Simplified Myers)

    private enum Edit: Equatable {
        case equal
        case insert
        case delete
    }

    private static func computeEdits(old: [String], new: [String]) -> [Edit] {
        let m = old.count
        let n = new.count

        // LCS-based approach: find longest common subsequence
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to produce edit script
        var edits: [Edit] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0, j > 0, old[i - 1] == new[j - 1] {
                edits.append(.equal)
                i -= 1; j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                edits.append(.insert)
                j -= 1
            } else {
                edits.append(.delete)
                i -= 1
            }
        }
        return edits.reversed()
    }

    // MARK: - Hunk Building

    private static func buildHunks(
        oldLines: [String],
        newLines: [String],
        edits: [Edit],
        context: Int
    ) -> [Hunk] {
        var hunks: [Hunk] = []
        var i = 0, oldLine = 0, newLine = 0

        while i < edits.count {
            // Skip equal lines
            var skipCount = 0
            while i + skipCount < edits.count, edits[i + skipCount] == .equal {
                skipCount += 1
            }
            let start = i
            i += skipCount
            oldLine += skipCount
            newLine += skipCount

            guard i < edits.count, edits[i] != .equal else { continue }

            // Collect changed block
            var changedLines: [DiffLineKind] = []
            let hunkOldStart = max(0, oldLine - context)
            let hunkNewStart = max(0, newLine - context)

            // Add preceding context
            if context > 0, start > 0 {
                let ctxStart = max(0, start - context)
                for k in ctxStart..<start {
                    let oi = oldLine - (start - k)
                    if oi >= 0, oi < oldLines.count {
                        changedLines.append(.unchanged(oldLines[oi]))
                    }
                }
            }

            // Add changed lines
            _ = i  // changeStart marker — keeps i position before processing edits
            while i < edits.count, edits[i] != .equal {
                switch edits[i] {
                case .delete:
                    if oldLine < oldLines.count {
                        changedLines.append(.removed(oldLines[oldLine]))
                    }
                    oldLine += 1
                case .insert:
                    if newLine < newLines.count {
                        changedLines.append(.added(newLines[newLine]))
                    }
                    newLine += 1
                case .equal:
                    break
                }
                i += 1
            }

            // Add trailing context
            var trailingContext = 0
            while trailingContext < context, i + trailingContext < edits.count, edits[i + trailingContext] == .equal {
                if newLine + trailingContext < newLines.count {
                    changedLines.append(.unchanged(newLines[newLine + trailingContext]))
                }
                trailingContext += 1
            }

            hunks.append(Hunk(
                oldStart: hunkOldStart + 1, // 1-indexed
                newStart: hunkNewStart + 1,
                lines: changedLines
            ))
        }

        return hunks
    }
}

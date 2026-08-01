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
            if fileManager.fileExists(atPath: refURL.path) {
                return try String(contentsOf: refURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return try resolvePackedRef(String(ref))
        }
        // Detached HEAD: raw is already the commit SHA
        return raw.isEmpty ? nil : raw
    }

    private func resolvePackedRef(_ ref: String) throws -> String? {
        let packedRefsURL = gitDir.appendingPathComponent("packed-refs")
        guard fileManager.fileExists(atPath: packedRefsURL.path) else { return nil }
        let contents = try String(contentsOf: packedRefsURL, encoding: .utf8)
        for line in contents.split(separator: "\n") {
            guard !line.hasPrefix("#"), !line.hasPrefix("^") else { continue }
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, parts[1] == ref {
                return String(parts[0])
            }
        }
        return nil
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
                    let childTree = try readObject(sha: sha)
                    var childOffset = 0
                    return try findInTree(
                        bytes: [UInt8](childTree),
                        offset: &childOffset,
                        components: components,
                        depth: depth + 1
                    )
                }
            }
            // Continue to next entry
        }
        return nil
    }

    // MARK: - Decompression

    private func decompress(_ data: Data) throws -> Data {
        // Apple's COMPRESSION_ZLIB decoder consumes the raw DEFLATE payload;
        // loose Git objects use an RFC 1950 zlib wrapper (2-byte header + Adler-32).
        guard data.count > 6 else { throw GitReaderError.invalidObject }
        let firstByte = data[data.startIndex]
        let secondByte = data[data.index(after: data.startIndex)]
        let headerValue = Int(firstByte) << 8 | Int(secondByte)
        guard firstByte & 0x0F == 8,
              headerValue.isMultiple(of: 31),
              secondByte & 0x20 == 0 else {
            throw GitReaderError.invalidObject
        }
        let deflated = data.dropFirst(2).dropLast(4)
        let maximumInflatedSize = 8 * 1_024 * 1_024
        var capacity = 64 * 1_024
        var inflated: Data?

        while capacity <= maximumInflatedSize {
            var destination = [UInt8](repeating: 0, count: capacity)
            let decodedCount = deflated.withUnsafeBytes { sourceBytes in
                guard let source = sourceBytes.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return destination.withUnsafeMutableBufferPointer { destinationBuffer in
                    compression_decode_buffer(
                        destinationBuffer.baseAddress!,
                        capacity,
                        source,
                        deflated.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if decodedCount > 0, decodedCount < capacity {
                inflated = Data(destination.prefix(decodedCount))
                break
            }
            capacity *= 2
        }

        guard let inflated else { throw GitReaderError.decompressionFailed }
        guard let nullIndex = inflated.firstIndex(of: 0), nullIndex > inflated.startIndex else {
            throw GitReaderError.invalidHeader
        }
        let headerData = inflated[..<nullIndex]
        guard let header = String(data: headerData, encoding: .utf8),
              let expectedSize = Int(header.split(separator: " ").last ?? "") else {
            throw GitReaderError.invalidHeader
        }
        let payload = Data(inflated[inflated.index(after: nullIndex)...])
        guard payload.count == expectedSize else {
            throw GitReaderError.sizeMismatch(expected: expectedSize, actual: payload.count)
        }
        return payload
    }

    enum GitReaderError: Error {
        case invalidObject
        case invalidHeader
        case sizeMismatch(expected: Int, actual: Int)
        case decompressionFailed
    }
}

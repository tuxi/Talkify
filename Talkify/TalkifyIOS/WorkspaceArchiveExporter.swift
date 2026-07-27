//
//  WorkspaceArchiveExporter.swift
//  Talkify
//
//  Created by Codex on 2026/7/22.
//

#if os(iOS)
import Foundation

/// 将当前工作区导出为标准 ZIP32（Store 模式）。
///
/// 使用流式读写，避免在移动设备上将整个项目载入内存。工作区内部状态与 Git
/// 对象不属于用户交付物，因此排除 `.codeagent`、`.git` 和符号链接。
enum WorkspaceArchiveExporter {

    static func export(workspaceURL: URL, displayName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try exportSynchronously(workspaceURL: workspaceURL, displayName: displayName)
        }.value
    }

    private static func exportSynchronously(workspaceURL: URL, displayName: String) throws -> URL {
        let fileManager = FileManager.default
        let root = workspaceURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExportError.workspaceUnavailable
        }

        let exportDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CodeAgentWorkspaceExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let archiveName = safeFileName(displayName.isEmpty ? root.lastPathComponent : displayName)
        let archiveURL = exportDirectory.appendingPathComponent("\(archiveName).zip")
        guard fileManager.createFile(atPath: archiveURL.path, contents: nil) else {
            throw ExportError.cannotCreateArchive
        }

        do {
            let handle = try FileHandle(forWritingTo: archiveURL)
            defer { try? handle.close() }
            try writeArchive(from: root, rootName: archiveName, to: handle, fileManager: fileManager)
            return archiveURL
        } catch {
            try? fileManager.removeItem(at: exportDirectory)
            throw error
        }
    }

    private static func writeArchive(
        from root: URL,
        rootName: String,
        to output: FileHandle,
        fileManager: FileManager
    ) throws {
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
        ]
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw ExportError.cannotReadWorkspace
        }

        var items: [(url: URL, relativePath: String, isDirectory: Bool, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let relativePath = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relativePath.isEmpty else { continue }

            let values = try url.resourceValues(forKeys: Set(resourceKeys))
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }

            let components = relativePath.split(separator: "/")
            if components.contains(where: { $0 == ".git" || $0 == ".codeagent" }) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard url.lastPathComponent != ".DS_Store" else { continue }

            items.append((
                url: url,
                relativePath: relativePath,
                isDirectory: values.isDirectory == true,
                modifiedAt: values.contentModificationDate ?? .now
            ))
        }
        if let enumerationError { throw enumerationError }
        items.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

        guard items.count + 1 <= Int(UInt16.max) else { throw ExportError.tooManyItems }

        var centralEntries: [CentralEntry] = []
        centralEntries.reserveCapacity(items.count + 1)
        centralEntries.append(try writeDirectoryEntry(
            name: "\(rootName)/",
            modifiedAt: .now,
            to: output
        ))

        for item in items {
            try Task.checkCancellation()
            let name = "\(rootName)/\(item.relativePath)" + (item.isDirectory ? "/" : "")
            if item.isDirectory {
                centralEntries.append(try writeDirectoryEntry(
                    name: name,
                    modifiedAt: item.modifiedAt,
                    to: output
                ))
            } else {
                centralEntries.append(try writeFileEntry(
                    sourceURL: item.url,
                    name: name,
                    modifiedAt: item.modifiedAt,
                    to: output
                ))
            }
        }

        let centralDirectoryOffset = try zip32Offset(of: output)
        for entry in centralEntries {
            try writeCentralEntry(entry, to: output)
        }
        let centralDirectoryEnd = try zip32Offset(of: output)
        let centralDirectorySize = centralDirectoryEnd - centralDirectoryOffset
        try output.write(contentsOf: endOfCentralDirectory(
            entryCount: UInt16(centralEntries.count),
            size: centralDirectorySize,
            offset: centralDirectoryOffset
        ))
    }

    private static func writeDirectoryEntry(
        name: String,
        modifiedAt: Date,
        to output: FileHandle
    ) throws -> CentralEntry {
        let nameData = try encodedName(name)
        let offset = try zip32Offset(of: output)
        let timestamp = dosTimestamp(for: modifiedAt)
        try output.write(contentsOf: localHeader(
            flags: utf8Flag,
            timestamp: timestamp,
            crc32: 0,
            compressedSize: 0,
            uncompressedSize: 0,
            nameData: nameData
        ))
        return CentralEntry(
            nameData: nameData,
            flags: utf8Flag,
            timestamp: timestamp,
            crc32: 0,
            size: 0,
            localHeaderOffset: offset,
            isDirectory: true
        )
    }

    private static func writeFileEntry(
        sourceURL: URL,
        name: String,
        modifiedAt: Date,
        to output: FileHandle
    ) throws -> CentralEntry {
        let nameData = try encodedName(name)
        let offset = try zip32Offset(of: output)
        let timestamp = dosTimestamp(for: modifiedAt)
        let flags = utf8Flag | dataDescriptorFlag
        try output.write(contentsOf: localHeader(
            flags: flags,
            timestamp: timestamp,
            crc32: 0,
            compressedSize: 0,
            uncompressedSize: 0,
            nameData: nameData
        ))

        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        var crc = CRC32()
        var byteCount: UInt64 = 0
        while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            byteCount += UInt64(chunk.count)
            guard byteCount <= UInt64(UInt32.max) else { throw ExportError.itemTooLarge(name) }
            crc.update(with: chunk)
            try output.write(contentsOf: chunk)
        }

        let size = UInt32(byteCount)
        let checksum = crc.finalized
        var descriptor = Data()
        descriptor.appendUInt32(0x08074b50)
        descriptor.appendUInt32(checksum)
        descriptor.appendUInt32(size)
        descriptor.appendUInt32(size)
        try output.write(contentsOf: descriptor)

        return CentralEntry(
            nameData: nameData,
            flags: flags,
            timestamp: timestamp,
            crc32: checksum,
            size: size,
            localHeaderOffset: offset,
            isDirectory: false
        )
    }

    private static func writeCentralEntry(_ entry: CentralEntry, to output: FileHandle) throws {
        var data = Data()
        data.appendUInt32(0x02014b50)
        data.appendUInt16(0x0314) // Unix, ZIP specification 2.0
        data.appendUInt16(20)
        data.appendUInt16(entry.flags)
        data.appendUInt16(0) // Store (no compression)
        data.appendUInt16(entry.timestamp.time)
        data.appendUInt16(entry.timestamp.date)
        data.appendUInt32(entry.crc32)
        data.appendUInt32(entry.size)
        data.appendUInt32(entry.size)
        data.appendUInt16(UInt16(entry.nameData.count))
        data.appendUInt16(0) // extra length
        data.appendUInt16(0) // comment length
        data.appendUInt16(0) // disk number
        data.appendUInt16(0) // internal attributes
        data.appendUInt32(entry.isDirectory ? 0x41ED0010 : 0x81A40000)
        data.appendUInt32(entry.localHeaderOffset)
        data.append(entry.nameData)
        try output.write(contentsOf: data)
    }

    private static func localHeader(
        flags: UInt16,
        timestamp: DOSTimestamp,
        crc32: UInt32,
        compressedSize: UInt32,
        uncompressedSize: UInt32,
        nameData: Data
    ) -> Data {
        var data = Data()
        data.appendUInt32(0x04034b50)
        data.appendUInt16(20)
        data.appendUInt16(flags)
        data.appendUInt16(0) // Store (no compression)
        data.appendUInt16(timestamp.time)
        data.appendUInt16(timestamp.date)
        data.appendUInt32(crc32)
        data.appendUInt32(compressedSize)
        data.appendUInt32(uncompressedSize)
        data.appendUInt16(UInt16(nameData.count))
        data.appendUInt16(0)
        data.append(nameData)
        return data
    }

    private static func endOfCentralDirectory(
        entryCount: UInt16,
        size: UInt32,
        offset: UInt32
    ) -> Data {
        var data = Data()
        data.appendUInt32(0x06054b50)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(entryCount)
        data.appendUInt16(entryCount)
        data.appendUInt32(size)
        data.appendUInt32(offset)
        data.appendUInt16(0)
        return data
    }

    private static func encodedName(_ name: String) throws -> Data {
        let data = Data(name.utf8)
        guard data.count <= Int(UInt16.max) else { throw ExportError.pathTooLong }
        return data
    }

    private static func zip32Offset(of handle: FileHandle) throws -> UInt32 {
        let offset = try handle.offset()
        guard offset <= UInt64(UInt32.max) else { throw ExportError.archiveTooLarge }
        return UInt32(offset)
    }

    private static func safeFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "Workspace" : cleaned).prefix(80))
    }

    private static func dosTimestamp(for date: Date) -> DOSTimestamp {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max(components.year ?? 1980, 1980), 2107)
        let month = min(max(components.month ?? 1, 1), 12)
        let day = min(max(components.day ?? 1, 1), 31)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        let second = min(max(components.second ?? 0, 0), 59)
        return DOSTimestamp(
            time: UInt16((hour << 11) | (minute << 5) | (second / 2)),
            date: UInt16(((year - 1980) << 9) | (month << 5) | day)
        )
    }

    private static let utf8Flag: UInt16 = 1 << 11
    private static let dataDescriptorFlag: UInt16 = 1 << 3

    private struct DOSTimestamp {
        let time: UInt16
        let date: UInt16
    }

    private struct CentralEntry {
        let nameData: Data
        let flags: UInt16
        let timestamp: DOSTimestamp
        let crc32: UInt32
        let size: UInt32
        let localHeaderOffset: UInt32
        let isDirectory: Bool
    }

    private struct CRC32 {
        private var value = UInt32.max

        mutating func update(with data: Data) {
            for byte in data {
                let index = Int((value ^ UInt32(byte)) & 0xff)
                value = Self.table[index] ^ (value >> 8)
            }
        }

        var finalized: UInt32 { value ^ UInt32.max }

        private static let table: [UInt32] = (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1
                    ? 0xEDB88320 ^ (value >> 1)
                    : value >> 1
            }
            return value
        }
    }

    private enum ExportError: LocalizedError {
        case workspaceUnavailable
        case cannotCreateArchive
        case cannotReadWorkspace
        case tooManyItems
        case itemTooLarge(String)
        case archiveTooLarge
        case pathTooLong

        var errorDescription: String? {
            switch self {
            case .workspaceUnavailable:
                return TalkifyLocalized.string("workspace.error.unavailable")
            case .cannotCreateArchive:
                return TalkifyLocalized.string("workspace.error.cannot_create_export")
            case .cannotReadWorkspace:
                return TalkifyLocalized.string("workspace.error.cannot_read")
            case .tooManyItems:
                return TalkifyLocalized.string("workspace.error.zip_limit")
            case .itemTooLarge(let name):
                return String(format: TalkifyLocalized.string("workspace.error.file_too_large"), name)
            case .archiveTooLarge:
                return TalkifyLocalized.string("workspace.error.workspace_too_large")
            case .pathTooLong:
                return TalkifyLocalized.string("workspace.error.long_path")
            }
        }
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
#endif

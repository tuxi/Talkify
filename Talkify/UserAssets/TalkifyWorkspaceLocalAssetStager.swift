import Foundation
import AgentKit
import CryptoKit
import UniformTypeIdentifiers

enum TalkifyLocalAssetError: Error, LocalizedError, Sendable {
    case invalidResource
    case unsupportedType
    case tooLarge
    case unsafeWorkspace
    case workspaceWriteAccessDenied
    case destinationExists
    case unreadable

    var errorDescription: String? {
        switch self {
        case .invalidResource:
            return "无法读取所选附件"
        case .unsupportedType:
            return "仅支持图片、PDF 和常用文档"
        case .tooLarge:
            return "PDF 或文档不能超过 20 MiB"
        case .unsafeWorkspace:
            return "附件目标不在当前工作区内"
        case .workspaceWriteAccessDenied:
            return "Talkify 没有当前工作区的写入权限，请重新选择该工作区后重试"
        case .destinationExists:
            return "工作区中已存在同名但内容不同的附件"
        case .unreadable:
            return "附件无法读取"
        }
    }
}

enum TalkifyLocalAssetPolicy {
    static let maximumDocumentBytes: Int64 = 20 * 1_024 * 1_024

    static let pickerContentTypes: [UTType] = {
        var types: [UTType] = [
            .image, .pdf, .plainText, .rtf, .json, .xml, .commaSeparatedText
        ]
        let identifiers = [
            "net.daringfireball.markdown",
            "org.openxmlformats.wordprocessingml.document",
            "org.openxmlformats.spreadsheetml.sheet",
            "org.openxmlformats.presentationml.presentation",
            "com.microsoft.word.doc",
            "com.microsoft.excel.xls",
            "com.microsoft.powerpoint.ppt",
            "com.apple.iwork.pages.pages",
            "com.apple.iwork.numbers.numbers",
            "com.apple.iwork.keynote.key"
        ]
        types.append(contentsOf: identifiers.compactMap(UTType.init))
        return types
    }()

    static func type(for url: URL) throws -> UTType {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw TalkifyLocalAssetError.invalidResource
        }
        if let contentType = values.contentType {
            return contentType
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type
        }
        throw TalkifyLocalAssetError.unsupportedType
    }

    static func classification(for type: UTType) throws -> (mimeType: String, kind: String) {
        if type.conforms(to: .image) {
            return (type.preferredMIMEType ?? "image/jpeg", "image")
        }
        if type.conforms(to: .pdf) {
            return ("application/pdf", "pdf")
        }
        guard pickerContentTypes.contains(where: { type.conforms(to: $0) }) else {
            throw TalkifyLocalAssetError.unsupportedType
        }
        return (type.preferredMIMEType ?? "application/octet-stream", "document")
    }

    static func validateDocument(at url: URL, type: UTType) throws -> Int64 {
        _ = try classification(for: type)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw TalkifyLocalAssetError.unreadable
        }
        let sizeBytes = Int64(size)
        guard sizeBytes <= maximumDocumentBytes else {
            throw TalkifyLocalAssetError.tooLarge
        }
        if type.conforms(to: .pdf) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard try handle.read(upToCount: 5) == Data("%PDF-".utf8) else {
                throw TalkifyLocalAssetError.unsupportedType
            }
        }
        return sizeBytes
    }

    static func safeFilename(_ proposed: String, fallbackExtension: String? = nil) -> String {
        var value = proposed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        value = String(value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        })
        value = URL(fileURLWithPath: value).lastPathComponent
        if value.isEmpty || value == "." || value == ".." {
            value = "attachment"
        }
        if value.utf8.count > 255 {
            let ext = (value as NSString).pathExtension
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            var base = (value as NSString).deletingPathExtension
            while "\(base)\(suffix)".utf8.count > 255, !base.isEmpty {
                base.removeLast()
            }
            value = base.isEmpty ? "attachment" : "\(base)\(suffix)"
        }
        if (value as NSString).pathExtension.isEmpty, let fallbackExtension {
            value += ".\(fallbackExtension)"
        }
        return value
    }
}

actor TalkifyWorkspaceLocalAssetStager: LocalUserAssetStaging {
    private let fileManager: FileManager
    private let fileStore: ManagedUserAssetFileStore
    private let normalizer: UserImageNormalizer
    private var stagedByDigest: [String: URL] = [:]

    init(
        fileStore: ManagedUserAssetFileStore,
        normalizer: UserImageNormalizer,
        fileManager: FileManager = .default
    ) {
        self.fileStore = fileStore
        self.normalizer = normalizer
        self.fileManager = fileManager
    }

    func stage(
        attachment: DraftAttachmentReference,
        workspaceRoot: URL
    ) async throws -> LocalUserAssetRef {
        guard let source = URL(string: attachment.resourceURI), source.isFileURL else {
            throw TalkifyLocalAssetError.invalidResource
        }
        let didAccess = source.startAccessingSecurityScopedResource()
        defer {
            if didAccess { source.stopAccessingSecurityScopedResource() }
        }

        let canonicalSource = source.resolvingSymlinksInPath()
        let sourceType = try TalkifyLocalAssetPolicy.type(for: canonicalSource)
        guard let parsedID = UUID(uuidString: attachment.id) else {
            throw TalkifyLocalAssetError.invalidResource
        }
        let id = parsedID.uuidString.lowercased()

        let prepared: PreparedAsset
        if sourceType.conforms(to: .image) {
            let managedSource: URL
            if normalizer.isManagedURL(canonicalSource) {
                managedSource = canonicalSource
            } else {
                managedSource = try normalizer.importFile(
                    from: canonicalSource,
                    attachmentID: id,
                    accountScope: "local-workspace"
                )
            }
            let normalized = try normalizer.normalize(
                sourceURL: managedSource,
                attachmentID: id,
                preferredFilename: attachment.displayName
            )
            prepared = PreparedAsset(
                url: normalized.fileURL,
                filename: TalkifyLocalAssetPolicy.safeFilename(normalized.filename),
                mimeType: normalized.mimeType,
                kind: "image",
                sizeBytes: normalized.sizeBytes,
                sha256: normalized.sha256
            )
        } else {
            let classification = try TalkifyLocalAssetPolicy.classification(for: sourceType)
            let size = try TalkifyLocalAssetPolicy.validateDocument(
                at: canonicalSource,
                type: sourceType
            )
            prepared = PreparedAsset(
                url: canonicalSource,
                filename: TalkifyLocalAssetPolicy.safeFilename(
                    attachment.displayName,
                    fallbackExtension: sourceType.preferredFilenameExtension
                ),
                mimeType: classification.mimeType,
                kind: classification.kind,
                sizeBytes: size,
                sha256: try Self.sha256(of: canonicalSource)
            )
        }

        let root = try canonicalWorkspaceRoot(workspaceRoot)
        let assetDirectory = root
            .appendingPathComponent(".codeagent/user-assets", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try createContainedDirectory(assetDirectory, root: root)
        let destination = assetDirectory.appendingPathComponent(prepared.filename)
        try assertContained(destination, in: root, allowMissingLeaf: true)

        if fileManager.fileExists(atPath: destination.path) {
            guard try Self.sha256(of: destination) == prepared.sha256 else {
                throw TalkifyLocalAssetError.destinationExists
            }
        } else if let duplicate = stagedByDigest[cacheKey(root: root, digest: prepared.sha256)],
                  fileManager.fileExists(atPath: duplicate.path),
                  try Self.sha256(of: duplicate) == prepared.sha256 {
            do {
                try fileManager.linkItem(at: duplicate, to: destination)
            } catch {
                try installWithoutOverwrite(from: prepared.url, to: destination)
            }
        } else {
            try installWithoutOverwrite(from: prepared.url, to: destination)
        }

        try assertContained(destination, in: root, allowMissingLeaf: false)
        guard try Self.sha256(of: destination) == prepared.sha256 else {
            throw TalkifyLocalAssetError.unreadable
        }
        stagedByDigest[cacheKey(root: root, digest: prepared.sha256)] = destination

        let relativePath = destination.path
            .dropFirst(root.path.hasSuffix("/") ? root.path.count : root.path.count + 1)
        let ref = LocalUserAssetRef(
            id: id,
            relativePath: String(relativePath),
            filename: prepared.filename,
            mimeType: prepared.mimeType,
            kind: prepared.kind,
            sizeBytes: prepared.sizeBytes,
            sha256: prepared.sha256
        )
        try ref.validate()
        return ref
    }

    private func canonicalWorkspaceRoot(_ url: URL) throws -> URL {
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw TalkifyLocalAssetError.unsafeWorkspace
        }
        return root
    }

    private func createContainedDirectory(_ directory: URL, root: URL) throws {
        try assertContained(directory, in: root, allowMissingLeaf: true)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw Self.mappedFilesystemError(error)
        }
        let resolved = directory.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let values = try resolved.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey
        ])
        guard resolved.path.hasPrefix(rootPath),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw TalkifyLocalAssetError.unsafeWorkspace
        }
    }

    private func installWithoutOverwrite(from source: URL, to destination: URL) throws {
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).staging")
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            try fileManager.copyItem(at: source, to: temporary)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            throw Self.mappedFilesystemError(error)
        }
    }

    private func assertContained(
        _ candidate: URL,
        in root: URL,
        allowMissingLeaf: Bool
    ) throws {
        let checked = allowMissingLeaf
            ? candidate.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(candidate.lastPathComponent)
            : candidate.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard checked.path.hasPrefix(rootPath) else {
            throw TalkifyLocalAssetError.unsafeWorkspace
        }
        if !allowMissingLeaf {
            let values = try checked.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw TalkifyLocalAssetError.unsafeWorkspace
            }
        }
    }

    private func cacheKey(root: URL, digest: String) -> String {
        "\(root.path)\0\(digest)"
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func mappedFilesystemError(_ error: Error) -> Error {
        let cocoa = error as NSError
        if cocoa.domain == NSCocoaErrorDomain,
           cocoa.code == NSFileWriteNoPermissionError {
            return TalkifyLocalAssetError.workspaceWriteAccessDenied
        }
        if let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == EPERM || underlying.code == EACCES {
            return TalkifyLocalAssetError.workspaceWriteAccessDenied
        }
        return error
    }
}

private struct PreparedAsset {
    let url: URL
    let filename: String
    let mimeType: String
    let kind: String
    let sizeBytes: Int64
    let sha256: String
}

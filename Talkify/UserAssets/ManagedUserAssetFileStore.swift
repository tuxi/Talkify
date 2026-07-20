import Foundation

enum ManagedUserAssetFileError: Error, LocalizedError, Sendable {
    case unavailable
    case invalidResource

    var errorDescription: String? {
        String(localized: "user-assets.error.unavailable")
    }
}

final class ManagedUserAssetFileStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) throws {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = support
                .appendingPathComponent("Talkify", isDirectory: true)
                .appendingPathComponent("UserAssets", isDirectory: true)
                .appendingPathComponent("Drafts", isDirectory: true)
        }
        try createDirectory(self.rootURL)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = self.rootURL
        try? root.setResourceValues(values)
    }

    func importFile(from sourceURL: URL, attachmentID: String, accountScope: String) throws -> URL {
        let safeScope = Self.pathComponent(accountScope)
        let safeID = Self.pathComponent(attachmentID)
        let directory = rootURL
            .appendingPathComponent(safeScope, isDirectory: true)
            .appendingPathComponent(safeID, isDirectory: true)
        try createDirectory(directory)

        let ext = sourceURL.pathExtension.lowercased()
        let safeExtension = ext.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        } ? String(ext.prefix(12)) : "image"
        let destination = directory.appendingPathComponent("source.\(safeExtension)")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            throw ManagedUserAssetFileError.unavailable
        }
        try protect(destination)
        return destination
    }

    func normalizedURL(for attachmentID: String, sourceURL: URL, extension ext: String) -> URL {
        sourceURL.deletingLastPathComponent()
            .appendingPathComponent("normalized-\(Self.pathComponent(attachmentID)).\(ext)")
    }

    func validateManagedURL(_ url: URL) throws {
        let standardizedRoot = rootURL.standardizedFileURL.path
        let standardizedURL = url.standardizedFileURL.path
        guard url.isFileURL,
              standardizedURL.hasPrefix(standardizedRoot + "/"),
              fileManager.fileExists(atPath: standardizedURL) else {
            throw ManagedUserAssetFileError.invalidResource
        }
    }

    func protect(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    func removeAttachmentFiles(referencedBy resourceURI: String) {
        guard let url = URL(string: resourceURI),
              (try? validateManagedURL(url)) != nil else { return }
        try? fileManager.removeItem(at: url.deletingLastPathComponent())
    }

    /// Removes abandoned local drafts only after a conservative expiry window.
    func removeExpiredFiles(olderThan age: TimeInterval = 30 * 24 * 60 * 60) {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory != true,
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func createDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func pathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = value.unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(filtered))
        return result.isEmpty ? "unknown" : String(result.prefix(128))
    }
}

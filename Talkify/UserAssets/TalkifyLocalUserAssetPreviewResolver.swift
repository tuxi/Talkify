import Foundation
import AgentKit

final class TalkifyLocalUserAssetPreviewResolver: LocalUserAssetPreviewResolving, @unchecked Sendable {
    func previewURL(
        for asset: LocalUserAssetRef,
        conversationID: String,
        workspaceRoot: URL
    ) async throws -> URL {
        try asset.validate()
        guard !conversationID.isEmpty else { throw TalkifyLocalAssetError.invalidResource }

        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw TalkifyLocalAssetError.unsafeWorkspace
        }

        let candidate = root
            .appendingPathComponent(asset.relativePath)
            .resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix),
              candidate.lastPathComponent == asset.filename else {
            throw TalkifyLocalAssetError.unsafeWorkspace
        }
        let values = try candidate.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == asset.sizeBytes,
              try TalkifyWorkspaceLocalAssetStager.sha256(of: candidate) == asset.sha256 else {
            throw TalkifyLocalAssetError.invalidResource
        }
        return candidate
    }
}

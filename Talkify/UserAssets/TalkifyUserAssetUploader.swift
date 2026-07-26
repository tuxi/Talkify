import Foundation
import AgentKit

enum TalkifyUserAssetError: Error, LocalizedError, Sendable {
    case uploadFailed
    case unavailable
    case invalidMetadata
    case accountChanged

    var errorDescription: String? {
        switch self {
        case .uploadFailed: return String(localized: "user-assets.error.upload")
        case .unavailable, .invalidMetadata, .accountChanged:
            return String(localized: "user-assets.error.expired")
        }
    }
}

final class TalkifyUserAssetUploader: UserAssetUploading, @unchecked Sendable {
    private let normalizer: UserImageNormalizer
    private let api: any UserAssetAPIProtocol
    private let ossUploader: any OSSUserAssetUploading
    private let accountScope: @Sendable () -> String

    init(
        normalizer: UserImageNormalizer,
        api: any UserAssetAPIProtocol,
        ossUploader: any OSSUserAssetUploading = OSSUserAssetUploader(),
        accountScope: @escaping @Sendable () -> String
    ) {
        self.normalizer = normalizer
        self.api = api
        self.ossUploader = ossUploader
        self.accountScope = accountScope
    }

    func upload(
        attachment: DraftAttachmentReference,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> UserAssetRef {
        let startingScope = accountScope()
        guard let sourceURL = URL(string: attachment.resourceURI), sourceURL.isFileURL else {
            throw TalkifyUserAssetError.unavailable
        }
        progress(0)
        try Task.checkCancellation()

        // 拖拽/粘贴等来源的文件可能在管理目录之外，需要先拷贝到 UserAssets/Drafts；
        // 已经由 picker 导入过的文件（已在管理目录内）则跳过，避免自我覆盖。
        let managedURL: URL
        if normalizer.isManagedURL(sourceURL) {
            managedURL = sourceURL
        } else {
            managedURL = try normalizer.importFile(
                from: sourceURL,
                attachmentID: attachment.id,
                accountScope: startingScope
            )
        }

        let image = try normalizer.normalize(
            sourceURL: managedURL,
            attachmentID: attachment.id,
            preferredFilename: attachment.displayName
        )
        progress(0.15)
        guard accountScope() == startingScope else { throw TalkifyUserAssetError.accountChanged }

        let initialization = try await api.initialize(UserAssetUploadInitRequest(
            filename: image.filename,
            contentType: image.mimeType,
            sizeBytes: image.sizeBytes
        ))
        guard accountScope() == startingScope else { throw TalkifyUserAssetError.accountChanged }
        try await ossUploader.upload(
            fileURL: image.fileURL,
            contentType: image.mimeType,
            initialization: initialization
        ) { value in
            progress(0.15 + min(max(value, 0), 1) * 0.75)
        }
        progress(0.9)
        try Task.checkCancellation()

        let completed = try await api.complete(UserAssetCompleteRequest(
            assetID: initialization.assetID,
            uploadID: initialization.uploadID,
            ossKey: initialization.objectKey,
            sha256: image.sha256
        ))
        guard accountScope() == startingScope else { throw TalkifyUserAssetError.accountChanged }
        try Self.validate(completed, expectedSize: image.sizeBytes)

        let reference = UserAssetRef(
            assetID: completed.assetID,
            sha256: image.sha256,
            kind: "image",
            mimeType: completed.contentType,
            filename: UserImageNormalizer.safeFilename(
                completed.filename,
                mimeType: completed.contentType
            )
        )
        try reference.validate()
        progress(1)
        return reference
    }

    func revalidate(_ asset: UserAssetRef) async throws -> UserAssetRef {
        let startingScope = accountScope()
        let remote = try await api.asset(id: asset.assetID)
        guard accountScope() == startingScope else { throw TalkifyUserAssetError.accountChanged }
        try Self.validate(remote, expectedSize: nil)
        let reference = UserAssetRef(
            assetID: remote.assetID,
            sha256: asset.sha256,
            kind: "image",
            mimeType: remote.contentType,
            filename: UserImageNormalizer.safeFilename(remote.filename, mimeType: remote.contentType)
        )
        try reference.validate()
        return reference
    }

    private static func validate(_ asset: GatewayUserAsset, expectedSize: Int64?) throws {
        guard asset.assetID > 0,
              asset.status == "active",
              asset.assetKind == "image",
              asset.contentType == "image/jpeg" || asset.contentType == "image/png",
              asset.sizeBytes > 0,
              asset.sizeBytes <= UserImageNormalizer.maximumImageBytes,
              expectedSize == nil || expectedSize == asset.sizeBytes,
              let width = asset.imageWidth,
              let height = asset.imageHeight,
              (UserImageNormalizer.minimumDimension...UserImageNormalizer.maximumDimension).contains(width),
              (UserImageNormalizer.minimumDimension...UserImageNormalizer.maximumDimension).contains(height) else {
            throw TalkifyUserAssetError.invalidMetadata
        }
    }
}

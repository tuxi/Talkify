import Foundation
import CoreKit

protocol OSSUserAssetUploading: Sendable {
    func upload(
        fileURL: URL,
        contentType: String,
        initialization: UserAssetUploadInitResponse,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

/// The only component that can see STS credentials and the object key.
struct OSSUserAssetUploader: OSSUserAssetUploading, Sendable {
    func upload(
        fileURL: URL,
        contentType: String,
        initialization: UserAssetUploadInitResponse,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try Task.checkCancellation()
        let client = OSSV2ClientManager(
            region: initialization.region,
            bucket: initialization.bucket,
            endpoint: initialization.endpoint,
            accessKeyId: initialization.sts.accessKeyID,
            accessKeySecret: initialization.sts.accessKeySecret,
            securityToken: initialization.sts.securityToken
        )
        do {
            _ = try await client.uploadFile(
                from: fileURL,
                key: initialization.objectKey,
                contentType: contentType,
                isForbidOerwrite: true,
                onProgress: progress
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Never propagate SDK diagnostics: they may contain a request URL or key.
            throw TalkifyUserAssetError.uploadFailed
        }
    }
}

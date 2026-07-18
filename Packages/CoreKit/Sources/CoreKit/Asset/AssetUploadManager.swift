//
//  AssetUploadManager.swift
//  CoreKit
//

import Foundation

// MARK: - Upload Progress

public enum AssetUploadPhase: Sendable {
    case initializing
    case uploading(progress: Double)
    case completing
    case done
    case failed(Error)
}

public enum AssetUploadError: Error, LocalizedError {
    case initFailed(String)
    case ossUploadFailed(String)
    case completeFailed(String)
    case notActive

    public var errorDescription: String? {
        switch self {
        case .initFailed(let msg): return "上传初始化失败: \(msg)"
        case .ossUploadFailed(let msg): return "OSS 上传失败: \(msg)"
        case .completeFailed(let msg): return "上传完成确认失败: \(msg)"
        case .notActive: return "服务端校验未通过，请重试"
        }
    }
}

// MARK: - AssetUploadManager

public final class AssetUploadManager: Sendable {
    private let assetService: AssetService

    public init(assetService: AssetService) {
        self.assetService = assetService
    }

    /// 编排完整上传流程: init → OSS SDK 直传 → complete
    /// - Returns: 上传完成后的 AssetBrief（含签名 URL）
    public func upload(
        localURL: URL,
        filename: String,
        assetKind: AssetKind,
        contentType: String? = nil,
        sizeBytes: Int64? = nil,
        businessType: String? = nil,
        onPhaseChange: (@Sendable (AssetUploadPhase) -> Void)? = nil
    ) async throws -> AssetBrief {
        
        if !FileManager.default.fileExists(atPath: localURL.path()) {
            throw APIError.invalidPath
        }

        // Phase 1: Init
        onPhaseChange?(.initializing)

        let initRequest = UploadInitRequest(
            assetKind: assetKind,
            filename: filename,
            contentType: contentType,
            sizeBytes: sizeBytes,
            businessType: businessType
        )

        let initResponse: UploadInitResponse
        do {
            initResponse = try await assetService.initUpload(initRequest)
        } catch {
            onPhaseChange?(.failed(AssetUploadError.initFailed(error.localizedDescription)))
            throw AssetUploadError.initFailed(error.localizedDescription)
        }

        // Phase 2: OSS SDK Upload
        let ossClient = OSSV2ClientManager(
            region: initResponse.region,
            bucket: initResponse.bucket,
            endpoint: initResponse.endpoint,
            accessKeyId: initResponse.sts.accessKeyId,
            accessKeySecret: initResponse.sts.accessKeySecret,
            securityToken: initResponse.sts.securityToken
        )

        do {
            try await ossClient.uploadFile(
                from: localURL,
                key: initResponse.objectKey,
                isForbidOerwrite: false,
                onProgress: { progress in
                    onPhaseChange?(.uploading(progress: progress))
                }
            )
        } catch {
            onPhaseChange?(.failed(AssetUploadError.ossUploadFailed(error.localizedDescription)))
            throw AssetUploadError.ossUploadFailed(error.localizedDescription)
        }

        // Phase 3: Complete
        onPhaseChange?(.completing)

        let completeRequest = UploadCompleteRequest(
            assetId: initResponse.assetId,
            uploadId: initResponse.uploadId,
            ossKey: initResponse.objectKey
        )

        let asset: AssetBrief
        do {
            asset = try await assetService.completeUpload(completeRequest)
        } catch {
            onPhaseChange?(.failed(AssetUploadError.completeFailed(error.localizedDescription)))
            throw AssetUploadError.completeFailed(error.localizedDescription)
        }

        guard asset.status == AssetStatus.active else {
            onPhaseChange?(.failed(AssetUploadError.notActive))
            throw AssetUploadError.notActive
        }

        onPhaseChange?(.done)
        return asset
    }
}

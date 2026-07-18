//
//  AssetModels.swift
//  CoreKit
//

import Foundation

// MARK: - Enums

public enum AssetClass: String, Codable, Sendable {
    case userUpload = "user_upload"
}

public enum AssetKind: String, Codable, Sendable {
    case image
    case video
    case audio
    case file
}

public enum AssetStatus: String, Codable, Sendable {
    case pending
    case active
    case deleted
}

public enum AssetVisibility: String, Codable, Sendable {
    case `private`
}

public enum DeleteMode: String, Codable, Sendable {
    case physical
    case soft
}

// MARK: - Upload Init

public struct UploadInitRequest: Sendable {
    public let assetClass: AssetClass
    public let assetKind: AssetKind
    public let filename: String
    public let contentType: String?
    public let sizeBytes: Int64?
    public let businessType: String?

    public init(
        assetClass: AssetClass = .userUpload,
        assetKind: AssetKind,
        filename: String,
        contentType: String? = nil,
        sizeBytes: Int64? = nil,
        businessType: String? = nil
    ) {
        self.assetClass = assetClass
        self.assetKind = assetKind
        self.filename = filename
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.businessType = businessType
    }
}

public struct STSInfo: Codable, Sendable {
    public let accessKeyId: String
    public let accessKeySecret: String
    public let securityToken: String
    public let expiration: Date

    enum CodingKeys: String, CodingKey {
        case accessKeyId = "access_key_id"
        case accessKeySecret = "access_key_secret"
        case securityToken = "security_token"
        case expiration
    }
}

public struct UploadInitResponse: Codable, Sendable {
    public let assetId: Int
    public let uploadId: String
    public let bucket: String
    public let region: String
    public let endpoint: String
    public let host: String
    public let dir: String
    public let objectKey: String
    public let sts: STSInfo
    public let asset: AssetBrief

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case uploadId = "upload_id"
        case bucket
        case region
        case endpoint
        case host
        case dir
        case objectKey = "object_key"
        case sts
        case asset
    }
}

// MARK: - Upload Complete

public struct UploadCompleteRequest: Sendable {
    public let assetId: Int
    public let uploadId: String
    public let ossKey: String

    public init(assetId: Int, uploadId: String, ossKey: String) {
        self.assetId = assetId
        self.uploadId = uploadId
        self.ossKey = ossKey
    }
}

// MARK: - Asset Brief (reusable)

public struct AssetBrief: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int {
        return assetId
    }
    public let assetId: Int
    public let url: String
    public let urlExpiresAt: Date?
    public let ossKey: String
    public let bucket: String
    public let assetClass: String
    public let assetKind: AssetKind
    public let visibility: String
    public let filename: String
    public let sizeBytes: Int64?
    public let contentType: String?
    public let status: AssetStatus
    public let canDelete: Bool
    public let refCount: Int
    public let createdAt: Date
    
    public var isVideo: Bool {
        return assetKind == .video
    }
    
    public init(assetId: Int, url: String, urlExpiresAt: Date?, ossKey: String, bucket: String, assetClass: String, assetKind: AssetKind, visibility: String, filename: String, sizeBytes: Int64?, contentType: String?, status: AssetStatus, canDelete: Bool, refCount: Int, createdAt: Date) {
        self.assetId = assetId
        self.url = url
        self.urlExpiresAt = urlExpiresAt
        self.ossKey = ossKey
        self.bucket = bucket
        self.assetClass = assetClass
        self.assetKind = assetKind
        self.visibility = visibility
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.contentType = contentType
        self.status = status
        self.canDelete = canDelete
        self.refCount = refCount
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case url
        case urlExpiresAt = "url_expires_at"
        case ossKey = "oss_key"
        case bucket
        case assetClass = "asset_class"
        case assetKind = "asset_kind"
        case visibility
        case filename
        case sizeBytes = "size_bytes"
        case contentType = "content_type"
        case status
        case canDelete = "can_delete"
        case refCount = "ref_count"
        case createdAt = "created_at"
    }
}

// MARK: - Asset List

public struct AssetListResponse: Codable, Sendable {
    public let items: [AssetBrief]
    public let page: Int
    public let pageSize: Int
    public let total: Int

    enum CodingKeys: String, CodingKey {
        case items
        case page
        case pageSize = "page_size"
        case total
    }
}

// MARK: - Delete Asset

public struct DeleteAssetResponse: Codable, Sendable {
    public let assetId: Int
    public let deleteMode: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case deleteMode = "delete_mode"
        case status
    }

    public var isPhysicalDelete: Bool { deleteMode == DeleteMode.physical.rawValue }
    public var isSoftDelete: Bool { deleteMode == DeleteMode.soft.rawValue }
}

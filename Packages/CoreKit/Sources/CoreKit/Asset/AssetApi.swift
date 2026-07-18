//
//  AssetApi.swift
//  CoreKit
//

import Foundation

public enum AssetApi: ApiEndpoint {

    case initUpload(UploadInitRequest)
    case completeUpload(UploadCompleteRequest)
    case listAssets(assetClass: String?, assetKind: AssetKind?, page: Int, pageSize: Int)
    case deleteAsset(assetId: Int)
    case getAsset(assetId: Int)

    public var path: String {
        switch self {
        case .initUpload:
            return "uploads/init"
        case .completeUpload:
            return "uploads/complete"
        case .listAssets:
            return "assets"
        case .deleteAsset(let assetId):
            return "assets/\(assetId)"
        case .getAsset(let assetId):
            return "assets/\(assetId)"
        }
    }

    public var method: HTTPMethod {
        switch self {
        case .initUpload, .completeUpload:
            return .post
        case .listAssets:
            return .get
        case .deleteAsset:
            return .delete
        case .getAsset:
            return .get
        }
    }

    public var parameters: [String: Sendable] {
        switch self {
        case .initUpload(let request):
            var params: [String: Sendable] = [
                "asset_class": request.assetClass.rawValue,
                "asset_kind": request.assetKind.rawValue,
                "filename": request.filename
            ]
            if let contentType = request.contentType {
                params["content_type"] = contentType
            }
            if let sizeBytes = request.sizeBytes {
                params["size_bytes"] = sizeBytes
            }
            if let businessType = request.businessType {
                params["business_type"] = businessType
            }
            return params

        case .completeUpload(let request):
            return [
                "asset_id": request.assetId,
                "upload_id": request.uploadId,
                "oss_key": request.ossKey
            ]

        case .listAssets(let assetClass, let assetKind, let page, let pageSize):
            var params: [String: Sendable] = [
                "page": page,
                "page_size": pageSize
            ]
            if let assetClass {
                params["asset_class"] = assetClass
            }
            if let assetKind {
                params["asset_kind"] = assetKind.rawValue
            }
            return params

        case .deleteAsset, .getAsset:
            return [:]
        }
    }

    public var encoding: ApiParameterEncoding {
        switch self {
        case .initUpload, .completeUpload:
            return .json
        case .listAssets, .deleteAsset, .getAsset:
            return .url
        }
    }
}

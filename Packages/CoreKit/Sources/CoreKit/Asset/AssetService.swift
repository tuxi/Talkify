//
//  AssetService.swift
//  CoreKit
//

import Foundation

public final class AssetService: Sendable {
    private let apiProvider: ApiProvider

    public init(apiProvider: ApiProvider) {
        self.apiProvider = apiProvider
    }

    public func initUpload(_ request: UploadInitRequest) async throws -> UploadInitResponse {
        try await apiProvider.request(endpoint: AssetApi.initUpload(request))
    }

    public func completeUpload(_ request: UploadCompleteRequest) async throws -> AssetBrief {
        try await apiProvider.request(endpoint: AssetApi.completeUpload(request))
    }

    public func listAssets(
        assetClass: String? = nil,
        assetKind: AssetKind? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> AssetListResponse {
        try await apiProvider.request(endpoint: AssetApi.listAssets(
            assetClass: assetClass,
            assetKind: assetKind,
            page: page,
            pageSize: pageSize
        ))
    }

    public func deleteAsset(assetId: Int) async throws -> DeleteAssetResponse {
        try await apiProvider.request(endpoint: AssetApi.deleteAsset(assetId: assetId))
    }
    
    public func getAsset(assetId: Int) async throws -> AssetBrief {
        try await apiProvider.request(endpoint: AssetApi.getAsset(assetId: assetId))
    }
}

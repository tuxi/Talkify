import Foundation
import CoreKit

protocol UserAssetAuthorizationProviding: Sendable {
    func userAssetAccessToken() async throws -> String
    func refreshUserAssetAccessToken() async throws
}

extension AuthManager: UserAssetAuthorizationProviding {
    nonisolated func userAssetAccessToken() async throws -> String {
        try await getValidAccessToken()
    }

    nonisolated func refreshUserAssetAccessToken() async throws {
        try await refreshAfterUnauthorized()
    }
}

struct UserAssetUploadInitRequest: Encodable, Sendable {
    let assetClass = "user_upload"
    let assetKind = "image"
    let businessType = "agent_user_attachment"
    let filename: String
    let contentType: String
    let sizeBytes: Int64

    enum CodingKeys: String, CodingKey {
        case assetClass = "asset_class"
        case assetKind = "asset_kind"
        case businessType = "business_type"
        case filename
        case contentType = "content_type"
        case sizeBytes = "size_bytes"
    }
}

struct UserAssetUploadInitResponse: Decodable, Sendable {
    let assetID: Int64
    let uploadID: String
    let bucket: String
    let region: String
    let endpoint: String
    let objectKey: String
    let sts: UserAssetSTS

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case uploadID = "upload_id"
        case bucket, region, endpoint
        case objectKey = "object_key"
        case sts
    }
}

struct UserAssetSTS: Decodable, Sendable {
    let accessKeyID: String
    let accessKeySecret: String
    let securityToken: String

    enum CodingKeys: String, CodingKey {
        case accessKeyID = "access_key_id"
        case accessKeySecret = "access_key_secret"
        case securityToken = "security_token"
    }
}

struct UserAssetCompleteRequest: Encodable, Sendable {
    let assetID: Int64
    let uploadID: String
    let ossKey: String
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case uploadID = "upload_id"
        case ossKey = "oss_key"
        case sha256
    }
}

struct GatewayUserAsset: Decodable, Sendable {
    let assetID: Int64
    let url: String?
    let urlExpiresAt: Date?
    let assetKind: String
    let filename: String
    let sizeBytes: Int64
    let imageWidth: Int?
    let imageHeight: Int?
    let contentType: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case url
        case urlExpiresAt = "url_expires_at"
        case assetKind = "asset_kind"
        case filename
        case sizeBytes = "size_bytes"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case contentType = "content_type"
        case status
    }
}

protocol UserAssetAPIProtocol: Sendable {
    func initialize(_ request: UserAssetUploadInitRequest) async throws -> UserAssetUploadInitResponse
    func complete(_ request: UserAssetCompleteRequest) async throws -> GatewayUserAsset
    func asset(id: Int64) async throws -> GatewayUserAsset
}

enum UserAssetAPIError: Error, LocalizedError, Sendable {
    case unauthorized
    case notFound
    case invalidResponse
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return String(localized: "user-assets.error.expired")
        case .notFound: return String(localized: "user-assets.error.expired")
        case .invalidResponse: return String(localized: "user-assets.error.upload")
        case .server: return String(localized: "user-assets.error.upload")
        }
    }
}

/// A deliberately quiet Gateway client. Upload responses contain credentials
/// and object paths, so this client does not use the app's debug HTTP logger.
final class UserAssetAPI: UserAssetAPIProtocol, @unchecked Sendable {
    private let baseURL: URL
    private let authorization: any UserAssetAuthorizationProviding
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        authorization: any UserAssetAuthorizationProviding,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authorization = authorization
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid date")
            )
        }
        self.decoder = decoder
    }

    func initialize(_ request: UserAssetUploadInitRequest) async throws -> UserAssetUploadInitResponse {
        try await send(path: "uploads/init", method: "POST", body: request)
    }

    func complete(_ request: UserAssetCompleteRequest) async throws -> GatewayUserAsset {
        try await send(path: "uploads/complete", method: "POST", body: request)
    }

    func asset(id: Int64) async throws -> GatewayUserAsset {
        try await send(path: "assets/\(id)", method: "GET", body: Optional<String>.none)
    }

    private func send<Response: Decodable & Sendable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        var didRefresh = false
        while true {
            let token = try await authorization.userAssetAccessToken()
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.httpMethod = method
            request.timeoutInterval = 50
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let body { request.httpBody = try encoder.encode(body) }

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UserAssetAPIError.invalidResponse
            }
            if http.statusCode == 401, !didRefresh {
                didRefresh = true
                try await authorization.refreshUserAssetAccessToken()
                continue
            }
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw UserAssetAPIError.unauthorized
            case 404: throw UserAssetAPIError.notFound
            default: throw UserAssetAPIError.server(status: http.statusCode)
            }
            let envelope = try decoder.decode(GatewayEnvelope<Response>.self, from: data)
            guard envelope.code == 0 || envelope.code == 200,
                  let payload = envelope.data else {
                throw UserAssetAPIError.invalidResponse
            }
            return payload
        }
    }
}

private struct GatewayEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let code: Int
    let data: Payload?
}

import XCTest
import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AgentKit
@testable import Talkify

final class UserImageNormalizerTests: XCTestCase {
    private var root: URL!
    private var store: ManagedUserAssetFileStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try ManagedUserAssetFileStore(rootURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testHEICBecomesJPEGAndSHAUsesFinalBytes() throws {
        let destinationTypes = CGImageDestinationCopyTypeIdentifiers() as! [String]
        guard destinationTypes.contains(UTType.heic.identifier) else {
            throw XCTSkip("HEIC encoder is unavailable")
        }
        let source = try writeImage(type: .heic, width: 80, height: 60)
        let result = try UserImageNormalizer(fileStore: store).normalize(
            sourceURL: source, attachmentID: "a", preferredFilename: "photo.heic"
        )
        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertEqual(result.fileURL.pathExtension, "jpg")
        let bytes = try Data(contentsOf: result.fileURL)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(result.sha256, digest)
    }

    func testOrientationIsAppliedAndMetadataRemoved() throws {
        let source = try writeImage(
            type: .jpeg,
            width: 40,
            height: 80,
            properties: [
                kCGImagePropertyOrientation: 6,
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.3]
            ]
        )
        let result = try UserImageNormalizer(fileStore: store).normalize(
            sourceURL: source, attachmentID: "b", preferredFilename: "camera.jpg"
        )
        XCTAssertEqual(result.width, 80)
        XCTAssertEqual(result.height, 40)
        let output = CGImageSourceCreateWithURL(result.fileURL as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as! [CFString: Any]
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    func testTransparentPNGPreservesAlpha() throws {
        let source = try writeImage(type: .png, width: 64, height: 64, alpha: true)
        let result = try UserImageNormalizer(fileStore: store).normalize(
            sourceURL: source, attachmentID: "c", preferredFilename: "alpha.png"
        )
        XCTAssertEqual(result.mimeType, "image/png")
        let output = CGImageSourceCreateImageAtIndex(
            CGImageSourceCreateWithURL(result.fileURL as CFURL, nil)!, 0, nil
        )!
        XCTAssertNotEqual(output.alphaInfo, .none)
    }

    func testLargeImageIsDownsampledAndFilenameIsSafe() throws {
        let source = try writeImage(type: .jpeg, width: 9_000, height: 40)
        let result = try UserImageNormalizer(fileStore: store).normalize(
            sourceURL: source, attachmentID: "d", preferredFilename: "../bad\\name.heic"
        )
        XCTAssertLessThanOrEqual(max(result.width, result.height), 8_192)
        XCTAssertEqual(result.filename, ".._bad_name.jpg")
        XCTAssertFalse(result.filename.contains("/"))
    }

    func testCombinedTwentyMiBLimit() {
        let image = NormalizedUserImage(
            fileURL: root, filename: "a.jpg", mimeType: "image/jpeg",
            sizeBytes: 10 * 1_024 * 1_024 + 1, width: 32, height: 32, sha256: String(repeating: "a", count: 64)
        )
        XCTAssertThrowsError(try UserImageNormalizer.validateCombinedSize([image, image]))
    }

    func testOversizedTransparentImageIsCompressedOrRejected() throws {
        let width = 2_048
        let height = 2_048
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in pixels.indices { pixels[index] = UInt8(truncatingIfNeeded: index &* 31) }
        let source = pixels.withUnsafeMutableBytes { bytes -> URL in
            let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let url = root.appendingPathComponent("noise.png")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return url
        }
        do {
            let result = try UserImageNormalizer(fileStore: store).normalize(
                sourceURL: source, attachmentID: "large", preferredFilename: "noise.png"
            )
            XCTAssertLessThanOrEqual(result.sizeBytes, UserImageNormalizer.maximumImageBytes)
        } catch UserImageNormalizationError.tooLarge {
            // Explicit rejection is also protocol-compliant.
        }
    }

    private func writeImage(
        type: UTType,
        width: Int,
        height: Int,
        alpha: Bool = false,
        properties: [CFString: Any] = [:]
    ) throws -> URL {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = alpha ? .premultipliedLast : .noneSkipLast
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: alphaInfo.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = root.appendingPathComponent("source-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "img")")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}

private actor MockAuthorization: UserAssetAuthorizationProviding {
    private(set) var refreshCount = 0
    func userAssetAccessToken() async throws -> String { refreshCount == 0 ? "old" : "new" }
    func refreshUserAssetAccessToken() async throws { refreshCount += 1 }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let result = try Self.lock.withLock { try Self.handler!(request) }
            client?.urlProtocol(self, didReceive: result.0, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class UserAssetAPITests: XCTestCase {
    func testInitFieldsAnd401RefreshOnce() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let auth = MockAuthorization()
        var calls = 0
        MockURLProtocol.handler = { request in
            calls += 1
            if calls == 1 {
                return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
            }
            let bodyData = try Self.bodyData(from: request)
            let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
            XCTAssertEqual(body["business_type"] as? String, "agent_user_attachment")
            XCTAssertEqual(body["content_type"] as? String, "image/jpeg")
            XCTAssertEqual(body["size_bytes"] as? Int, 123)
            let json = #"{"code":0,"data":{"asset_id":1,"upload_id":"up","bucket":"b","region":"r","endpoint":"e","object_key":"private-key","sts":{"access_key_id":"id","access_key_secret":"secret","security_token":"token"}}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let api = UserAssetAPI(
            baseURL: URL(string: "https://example.com/api/v1")!,
            authorization: auth,
            session: URLSession(configuration: config)
        )
        _ = try await api.initialize(.init(filename: "a.jpg", contentType: "image/jpeg", sizeBytes: 123))
        let refreshCount = await auth.refreshCount
        XCTAssertEqual(refreshCount, 1)
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else {
            throw UserAssetAPIError.invalidResponse
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? UserAssetAPIError.invalidResponse }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private actor MockUserAssetAPI: UserAssetAPIProtocol {
    var assets: [GatewayUserAsset]
    private(set) var getCount = 0
    init(assets: [GatewayUserAsset]) { self.assets = assets }
    func initialize(_ request: UserAssetUploadInitRequest) async throws -> UserAssetUploadInitResponse { fatalError() }
    func complete(_ request: UserAssetCompleteRequest) async throws -> GatewayUserAsset { fatalError() }
    func asset(id: Int64) async throws -> GatewayUserAsset {
        getCount += 1
        guard !assets.isEmpty else { throw UserAssetAPIError.notFound }
        return assets.removeFirst()
    }
}

final class UserAssetResolverTests: XCTestCase {
    func testExpiredPreviewRefreshes() async throws {
        let remote = gatewayAsset(expires: Date().addingTimeInterval(10))
        let api = MockUserAssetAPI(assets: [remote, remote])
        let resolver = TalkifyUserAssetPreviewResolver(api: api, accountScope: { "1" })
        let ref = UserAssetRef(assetID: 1, mimeType: "image/jpeg", filename: "a.jpg")
        _ = try await resolver.previewURL(for: ref)
        _ = try await resolver.previewURL(for: ref)
        let getCount = await api.getCount
        XCTAssertEqual(getCount, 2)
    }

    func testRevalidateRejectsInactiveAsset() async throws {
        let inactive = gatewayAsset(expires: Date().addingTimeInterval(60), status: "deleted")
        let api = MockUserAssetAPI(assets: [inactive])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try ManagedUserAssetFileStore(rootURL: root)
        let uploader = TalkifyUserAssetUploader(
            normalizer: UserImageNormalizer(fileStore: store), api: api, accountScope: { "1" }
        )
        let ref = UserAssetRef(assetID: 1, mimeType: "image/jpeg", filename: "a.jpg")
        do {
            _ = try await uploader.revalidate(ref)
            XCTFail("Expected inactive asset rejection")
        } catch is TalkifyUserAssetError {}
        try? FileManager.default.removeItem(at: root)
    }

    func testRevalidateRejects404() async throws {
        let api = MockUserAssetAPI(assets: [])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try ManagedUserAssetFileStore(rootURL: root)
        let uploader = TalkifyUserAssetUploader(
            normalizer: UserImageNormalizer(fileStore: store), api: api, accountScope: { "1" }
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await uploader.revalidate(
                UserAssetRef(assetID: 404, mimeType: "image/jpeg", filename: "missing.jpg")
            )
        }
        try? FileManager.default.removeItem(at: root)
    }

    private func gatewayAsset(expires: Date, status: String = "active") -> GatewayUserAsset {
        GatewayUserAsset(
            assetID: 1, url: "https://example.com/preview", urlExpiresAt: expires,
            assetKind: "image", filename: "a.jpg", sizeBytes: 100,
            imageWidth: 32, imageHeight: 32, contentType: "image/jpeg", status: status
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}

final class ManagedUserAssetLocalStateStoreTests: XCTestCase {
    func testRemovingDraftAttachmentReclaimsManagedFiles() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = try ManagedUserAssetFileStore(rootURL: temporary.appendingPathComponent("files"))
        let source = temporary.appendingPathComponent("source.jpg")
        try Data([1, 2, 3]).write(to: source)
        let managed = try files.importFile(from: source, attachmentID: "attachment", accountScope: "1")
        let sqlite = SQLiteConversationLocalStateStore(
            databaseURL: temporary.appendingPathComponent("state.sqlite")
        )
        let store = ManagedUserAssetLocalStateStore(underlying: sqlite, fileStore: files)
        let key = ConversationLocalStateKey.draft(UUID())
        try store.save(ConversationLocalState(composerDraft: ComposerDraft(attachments: [
            DraftAttachmentReference(id: "attachment", displayName: "a.jpg", resourceURI: managed.absoluteString)
        ])), for: key)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.path))
        try store.updateState(for: key) { $0.composerDraft.attachments.removeAll() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
        try? FileManager.default.removeItem(at: temporary)
    }
}

private struct StubAssetUploader: UserAssetUploading {
    func upload(
        attachment: DraftAttachmentReference,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> UserAssetRef {
        UserAssetRef(assetID: 1, mimeType: "image/jpeg", filename: "a.jpg")
    }
    func revalidate(_ asset: UserAssetRef) async throws -> UserAssetRef { asset }
}

private struct StubPreviewResolver: UserAssetPreviewResolving {
    func previewURL(for asset: UserAssetRef) async throws -> URL {
        URL(string: "https://example.com/preview")!
    }
}

final class UserAssetDependencyInjectionTests: XCTestCase {
    @MainActor
    func testWorkspaceStoreReceivesAllHostUserAssetCapabilities() {
        let dependencies = AgentDependencies(
            client: DefaultAgentClient(),
            userAssetPicker: { [] },
            userAssetUploader: StubAssetUploader(),
            userAssetPreviewResolver: StubPreviewResolver()
        )
        let store = WorkspaceView.makeStore(dependencies: dependencies)
        XCTAssertTrue(store.canSelectUserAssets)
        XCTAssertNotNil(store.userAssetPreviewResolver)
    }
}

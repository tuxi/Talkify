import Foundation
import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct NormalizedUserImage: Sendable {
    let fileURL: URL
    let filename: String
    let mimeType: String
    let sizeBytes: Int64
    let width: Int
    let height: Int
    let sha256: String
}

enum UserImageNormalizationError: Error, LocalizedError, Sendable {
    case unsupportedFormat
    case unsupportedDimensions
    case tooLarge
    case combinedSizeTooLarge
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return String(localized: "user-assets.error.format")
        case .unsupportedDimensions: return String(localized: "user-assets.error.dimensions")
        case .tooLarge, .combinedSizeTooLarge: return String(localized: "user-assets.error.too-large")
        case .unreadable: return String(localized: "user-assets.error.unavailable")
        }
    }
}

struct UserImageNormalizer: Sendable {
    static let maximumDimension = 8_192
    static let minimumDimension = 32
    static let maximumImageBytes: Int64 = 10 * 1_024 * 1_024
    static let maximumCombinedBytes: Int64 = 20 * 1_024 * 1_024

    let fileStore: ManagedUserAssetFileStore

    /// 将外部文件（拖拽、粘贴等来源）拷贝到管理目录，后续 normalize 才能通过安全校验。
    func importFile(from sourceURL: URL, attachmentID: String, accountScope: String) throws -> URL {
        try fileStore.importFile(from: sourceURL, attachmentID: attachmentID, accountScope: accountScope)
    }

    /// 检查 URL 是否已在管理目录内且文件存在，用于判断是否需要先 import。
    func isManagedURL(_ url: URL) -> Bool {
        (try? fileStore.validateManagedURL(url)) != nil
    }

    func normalize(
        sourceURL: URL,
        attachmentID: String,
        preferredFilename: String
    ) throws -> NormalizedUserImage {
        try fileStore.validateManagedURL(sourceURL)
        guard let source = CGImageSourceCreateWithURL(
            sourceURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), CGImageSourceGetCount(source) > 0 else {
            throw UserImageNormalizationError.unsupportedFormat
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = Self.integer(properties[kCGImagePropertyPixelWidth]),
              let rawHeight = Self.integer(properties[kCGImagePropertyPixelHeight]),
              rawWidth >= Self.minimumDimension,
              rawHeight >= Self.minimumDimension else {
            throw UserImageNormalizationError.unsupportedDimensions
        }

        var targetMax = min(max(rawWidth, rawHeight), Self.maximumDimension)
        var quality = 0.88
        var image = try Self.thumbnail(source: source, maximumPixelSize: targetMax)
        let sourceType: UTType? = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        // Some HEIC/JPEG decoders expose an opaque padding alpha channel. It is
        // not transparency and must not force a PNG output.
        let isOpaquePhoto = sourceType?.conforms(to: .heic) == true
            || sourceType?.conforms(to: .heif) == true
            || sourceType?.conforms(to: .jpeg) == true
        let isTransparent = !isOpaquePhoto && Self.hasAlpha(image)
        let mimeType = isTransparent ? "image/png" : "image/jpeg"
        let ext = isTransparent ? "png" : "jpg"
        let filename = Self.safeFilename(preferredFilename, mimeType: mimeType)

        var encoded = try Self.encode(image, mimeType: mimeType, quality: quality)
        while Int64(encoded.count) > Self.maximumImageBytes {
            if !isTransparent, quality > 0.56 {
                quality = max(0.55, quality - 0.08)
            } else {
                let nextMax = Int(Double(targetMax) * 0.85)
                guard nextMax >= Self.minimumDimension else {
                    throw UserImageNormalizationError.tooLarge
                }
                targetMax = nextMax
                quality = isTransparent ? 1 : 0.82
                image = try Self.thumbnail(source: source, maximumPixelSize: targetMax)
            }
            encoded = try Self.encode(image, mimeType: mimeType, quality: quality)
        }

        guard image.width >= Self.minimumDimension,
              image.height >= Self.minimumDimension,
              image.width <= Self.maximumDimension,
              image.height <= Self.maximumDimension else {
            throw UserImageNormalizationError.unsupportedDimensions
        }

        let outputURL = fileStore.normalizedURL(
            for: attachmentID,
            sourceURL: sourceURL,
            extension: ext
        )
        do {
            try encoded.write(to: outputURL, options: .atomic)
            try fileStore.protect(outputURL)
        } catch {
            throw UserImageNormalizationError.unreadable
        }
        let digest = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        return NormalizedUserImage(
            fileURL: outputURL,
            filename: filename,
            mimeType: mimeType,
            sizeBytes: Int64(encoded.count),
            width: image.width,
            height: image.height,
            sha256: digest
        )
    }

    static func validateCombinedSize(_ images: [NormalizedUserImage]) throws {
        let total = images.reduce(Int64(0)) { $0 + $1.sizeBytes }
        guard total <= maximumCombinedBytes else {
            throw UserImageNormalizationError.combinedSizeTooLarge
        }
    }

    static func safeFilename(_ proposed: String, mimeType: String?) -> String {
        var value = proposed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        value = URL(fileURLWithPath: value).lastPathComponent
        if value == "." || value == ".." || value.isEmpty { value = "image" }

        if let mimeType {
            let ext = mimeType == "image/png" ? "png" : "jpg"
            let base = (value as NSString).deletingPathExtension
            value = "\(base.isEmpty ? "image" : base).\(ext)"
        }
        while value.utf8.count > 255, !value.isEmpty { value.removeLast() }
        if value.isEmpty || value == "." || value == ".." { return "image.jpg" }
        return value
    }

    private static func thumbnail(source: CGImageSource, maximumPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw UserImageNormalizationError.unsupportedFormat
        }
        return image
    }

    private static func encode(_ image: CGImage, mimeType: String, quality: Double) throws -> Data {
        let data = NSMutableData()
        let type = mimeType == "image/png" ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            type as CFString,
            1,
            nil
        ) else { throw UserImageNormalizationError.unsupportedFormat }
        let properties: CFDictionary = mimeType == "image/jpeg"
            ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            : [:] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw UserImageNormalizationError.unsupportedFormat
        }
        return data as Data
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .premultipliedLast, .premultipliedFirst, .last, .first:
            return true
        default:
            return false
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        return nil
    }
}

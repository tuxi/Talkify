//
//  OSSClientManager.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/13.
//

import Foundation
import AlibabaCloudOSS // 使用 V2 SDK
import UniformTypeIdentifiers // 用于更强大的 MIME 类型识别

public struct OSSStsCredential: Sendable {
    public let accessKeyId: String
    public let accessKeySecret: String
    public let securityToken: String?
    public let userId: String
    
    public init(accessKeyId: String, accessKeySecret: String, securityToken: String?, userId: String) {
        self.accessKeyId = accessKeyId
        self.accessKeySecret = accessKeySecret
        self.securityToken = securityToken
        self.userId = userId
    }
}



/// 凭证提供者协议：支持静态和动态 STS 拉取
public protocol OSSCredentialsProvider: Sendable {
    func getCredentials() async throws -> OSSStsCredential
}

// 静态凭证（用于测试或主账号 AK/SK）
public struct OSSStaticProvider: OSSCredentialsProvider {
    public func getCredentials() async throws -> OSSStsCredential {
        return OSSStsCredential(accessKeyId: accessKeyId, accessKeySecret: accessKeySecret, securityToken: securityToken, userId: userID)
    }
    
    let accessKeyId: String
    let accessKeySecret: String
    let securityToken: String?
    let userID: String
    
    public init(accessKeyId: String, accessKeySecret: String, securityToken: String? = nil, userID: String) {
        self.accessKeyId = accessKeyId
        self.accessKeySecret = accessKeySecret
        self.securityToken = securityToken
        self.userID = userID
    }
}

/// 适配阿里云 SDK 的桥接类
private final class OSSSDKBridgeProvider: CredentialsProvider, @unchecked Sendable {
    private let provider: any OSSCredentialsProvider
    private(set) var lastCredential: OSSStsCredential?
    
    init(provider: any OSSCredentialsProvider) {
        self.provider = provider
    }
    
    func getCredentials() async throws -> Credentials {
        let cred = try await provider.getCredentials()
        self.lastCredential = cred // 缓存下来，后面拿 userId
        
        return Credentials(
            accessKeyId: cred.accessKeyId,
            accessKeySecret: cred.accessKeySecret,
            securityToken: cred.securityToken
        )
    }
}

// 文件上传的结果
public struct OSSUploadResult: Sendable {
    public let key: String     // 相对路径
    public let fullURL: URL // 完整访问地址
    public let eTag: String?   // 校验码
}

/// 基于 AlibabaCloudOSS V2 封装的 Swift 6 客户端
/// 使用 Actor 保证并发安全
public actor OSSV2ClientManager {
    
    private let client: Client
    private let bucket: String
    private let endpoint: String?
    private let region: String
    // 持有 bridge，才能随时拿 userId
    private let bridgeProvider: OSSSDKBridgeProvider?
    
    /// 初始化 OSS 客户端
    /// - Parameters:
    ///   - region: 区域，例如 "cn-hangzhou"
    ///   - bucket: 存储桶名称
    ///   - endpoint: 可选的自定义 Endpoint
    ///   - accessKeyId: 账号 ID
    ///   - accessKeySecret: 账号 Secret
    ///   - securityToken: 如果使用临时凭证 STS，请传入此参数
    public init(
        region: String,
        bucket: String,
        endpoint: String? = nil,
        accessKeyId: String,
        accessKeySecret: String,
        securityToken: String? = nil
    ) {
        /*
         let ossManager = OSSV2ClientManager(
             region: "cn-beijing",
             bucket: "dreamlog",
             endpoint: "oss-cn-beijing.aliyuncs.com",
             accessKeyId: "xxx",
             accessKeySecret: "xxx",
         )
         */
        self.bucket = bucket
        self.endpoint = endpoint
        self.region = region
        
        // 1. 配置凭证
        let credentialsProvider = StaticCredentialsProvider(
            accessKeyId: accessKeyId,
            accessKeySecret: accessKeySecret,
            securityToken: securityToken
        )
        
        // 2. 配置 Client
        let config = Configuration.default()
            .withRegion(region)
            .withCredentialsProvider(credentialsProvider)
        
        if let endpoint = endpoint {
            config.withEndpoint(endpoint)
        }
        
        config.endpoint
        self.bridgeProvider = nil
        self.client = Client(config)
    }
    
    /// 初始化方法：接受一个协议对象
    public init(
        region: String,
        bucket: String,
        endpoint: String? = nil,
        provider: any OSSCredentialsProvider
    ) {
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
        
        let bridgeProvider = OSSSDKBridgeProvider(provider: provider)
        
        let config = Configuration.default()
            .withRegion(region)
            .withCredentialsProvider(bridgeProvider)
        
        if let endpoint = endpoint {
            config.withEndpoint(endpoint)
        }
        self.bridgeProvider = bridgeProvider
        self.client = Client(config)
    }
    
    
    /// 异步获取 userId，主动刷新凭证
    public func currentUserId() async throws -> String {
        guard let bridge = bridgeProvider else {
            throw NSError(domain: "OSS", code: -1, userInfo: ["message": "仅 STS 模式支持 userId"])
        }
        
        // 如果已经有缓存，直接返回
        if let userId = bridge.lastCredential?.userId {
            return userId
        }
        
        // 主动获取一次凭证，确保 userId 存在
        let cred = try await bridge.getCredentials()
        guard let userId = bridge.lastCredential?.userId else {
            throw NSError(domain: "OSS", code: -2, userInfo: ["message": "STS 未返回 userId"])
        }
        return userId
    }
    
    /// 上传 Data 到 OSS
    /// - Parameters:
    ///   - data: 要上传的二进制数据
    ///   - key: OSS 存储路径 (例如 "images/avatar.jpg")
    ///   - contentType: MIME 类型
    /// - Returns: 上传成功后的结果 (包含 ETag 等)
    @discardableResult
    public func uploadData(_ data: Data, key: String, contentType: String? = nil) async throws -> PutObjectResult {
        // V2 SDK 使用 Body.data 包装
        var request = PutObjectRequest(
            bucket: self.bucket,
            key: key,
            body: .data(data)
        )
        
        if let contentType = contentType {
            request.contentType = contentType
        }
        
        return try await client.putObject(request)
    }
    
    /// 上传本地文件到 OSS
    /// - Parameters:
    ///   - fileURL: 本地文件路径
    ///   - key: OSS 存储路径
    @discardableResult
    public func uploadFile(from fileURL: URL, key: String, isForbidOerwrite: Bool = true, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> OSSUploadResult {
        // V2 SDK 使用 Body.file 包装
        var request = PutObjectRequest(
            bucket: self.bucket,
            key: key,
            body: .file(fileURL)
        )
        
        // 自动根据后缀设置 Content-Type
        request.contentType = mimeType(for: fileURL.pathExtension)
        let internalDelegate = InternalProgressDelegate(handler: onProgress)
        request.progress = internalDelegate
        
        // 如果文件已存在，返回 409 Conflict 错误，不再覆盖
        request.addHeader("x-oss-forbid-overwrite", isForbidOerwrite ? "true": "false")
        let result = try await client.putObject(request)
        
        // 拼接地址，如果是自定义域名则用自定义域名
        let domain = "\(self.bucket).oss-\(self.region).aliyuncs.com"
        // https://dreamlog.oss-cn-beijing.aliyuncs.com/dreams/images/2026/03/13/1/42160c473ea54b4c801222fbfec424c9.png
        let url = URL(string: "https://\(domain)/\(key)")!
        
        return OSSUploadResult(
            key: key,
            fullURL: url,
            eTag: result.etag
        )
    }
    
    // MARK: - 上传头像（自动 userId，无需传参）
    @discardableResult
    public func uploadAvatar(
        from fileURL: URL,
        ext: String? = nil,
    ) async throws -> OSSUploadResult {
        var fileEx = fileURL.pathExtension
        if let ext, !ext.isEmpty {
            fileEx = ext
        }
        let userId = try await currentUserId()
        let key = OSSPathHelper.avatarPath(userId: userId, ext: fileEx)
        return try await uploadFile(from: fileURL, key: key, isForbidOerwrite: false)
    }
    
    @discardableResult
    public func userAssetPath(
        from fileURL: URL,
        type: OSSResourceType,
        subDir: OSSSubDir = .common,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> OSSUploadResult {
        let userId = try await currentUserId()
        let ext = fileURL.pathExtension
        let key = OSSPathHelper.userAssetPath(type: type, userId: userId, fileExtension: ext)
        return try await uploadFile(from: fileURL, key: key, onProgress: onProgress)
    }
    
    // MARK: - 上传业务文件（自动 userId）
    @discardableResult
    public func uploadBusinessFile(
        from fileURL: URL,
        module: OSSServiceModule,
        type: OSSResourceType,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> OSSUploadResult {
        let userId = try await currentUserId()
        let ext = fileURL.pathExtension
        let key = OSSPathHelper.businessPath(
            module: module,
            type: type,
            userId: userId,
            fileExtension: ext
        )
        return try await uploadFile(from: fileURL, key: key, onProgress: onProgress)
    }
    
    /// 上传本地文件到指定目录，自动生成随机文件名
    /// - Parameters:
    ///   - fileURL: 本地文件路径
    ///   - directory: OSS 目录名称 (如 "avatars" 或 "dreams/outputs")
    @discardableResult
    public func uploadFile(from fileURL: URL, directory: String) async throws -> OSSUploadResult {
        // 1. 获取原文件后缀
        let fileExtension = fileURL.pathExtension
        
        // 2. 生成随机文件名 (UUID) 并拼接路径
        let randomFileName = UUID().uuidString.lowercased()
        let fileNameWithExt = fileExtension.isEmpty ? randomFileName : "\(randomFileName).\(fileExtension)"
        
        // 3. 处理目录路径分隔符
        let cleanDir = directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let objectKey = cleanDir.isEmpty ? fileNameWithExt : "\(cleanDir)/\(fileNameWithExt)"
        
        // 4. 调用原有的上传逻辑
        return try await uploadFile(from: fileURL, key: objectKey)
    }
    
    /// 尝试“秒传”逻辑
    public func smartUpload(from localURL: URL, directory: String) async throws -> OSSUploadResult {
        let md5 = try localURL.computeMD5()
        let ext = localURL.pathExtension
        
        // 注意：这里建议 Key 的命名规则包含 MD5，或者将 MD5 存入 OSS 的元数据
        // 方案 A：直接用 MD5 作为文件名 (最简单去重)
        let objectKey = "\(directory)/\(md5).\(ext)"
        
        do {
            // 尝试获取文件信息
            let headRequest = HeadObjectRequest(bucket: self.bucket, key: objectKey)
            let headResult = try await client.headObject(headRequest)
            
            // 如果没报错，说明文件已存在，直接返回结果
            let domain = self.endpoint ?? "\(self.bucket).oss-\(self.region).aliyuncs.com"
            return OSSUploadResult(
                key: objectKey,
                fullURL: URL(string: "https://\(domain)/\(objectKey)")!,
                eTag: headResult.etag
            )
        } catch {
            // 如果报错（通常是 404 Not Found），则继续执行上传
            return try await uploadFile(from: localURL, key: objectKey)
        }
    }
    
}

/// 使用 nonisolated 类专门负责接收 SDK 的同步进度回调
private final class InternalProgressDelegate: ProgressDelegate, @unchecked Sendable {
    let handler: (@Sendable (Double) -> Void)?
    
    init(handler: (@Sendable (Double) -> Void)?) {
        self.handler = handler
    }
    
    /// SDK 同步回调接口
    nonisolated func onProgress(_ bytesIncrement: Int64, _ totalBytesTransferred: Int64, _ totalBytesExpected: Int64) {
        // bytesIncrement: 本次上传的字节数
        // totalBytesTransferred: 已上传的总字节数
        // totalBytesExpected: 整个文件的总大小
        guard totalBytesExpected > 0 else { return }
        let progress = Double(totalBytesTransferred) / Double(totalBytesExpected)
        
        // 触发闭包
        handler?(progress)
    }
}

/// 识别 MIME 类型 (基于系统 UTType)
private func mimeType(for pathExtension: String) -> String {
    // iOS 14+ 推荐使用 UTType 识别，非常全面
    if let type = UTType(filenameExtension: pathExtension),
       let mime = type.preferredMIMEType {
        return mime
    }
    
    // 兜底常用类型
    switch pathExtension.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "mp4": return "video/mp4"
    case "json": return "application/json"
    default: return "application/octet-stream"
    }
}

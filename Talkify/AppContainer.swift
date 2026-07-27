//
//  AppContainer.swift
//  Talkify
//
//  Talkify dependency container: identity, API services, AgentKit, and client tools.
//

import Foundation
import AgentKit
import CoreKit
import FeatureAuth
import ClientToolsKit

struct BaseHeader: Encodable, Sendable {
    let deviceId: String
    let deviceType: String
    let deviceName: String
    let os: String
    let appVersion: String
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "X-Device-ID"
        case deviceType = "X-Device-Type"
        case deviceName = "X-Device-Name"
        case os = "X-OS-Version"
        case appVersion = "X-App-Version"
    }
    
    /// 从DeviceInfo初始化BaseHeader
    init(deviceInfo: DeviceInfo) {
        self.deviceId = deviceInfo.deviceId
        self.deviceType = deviceInfo.deviceType
        self.deviceName = deviceInfo.deviceName
        self.os = deviceInfo.osVersion
        self.appVersion = deviceInfo.appVersion
    }
    
    /// 转换为字典格式（用于设置header）
    func toDictionary() -> [String: String]? {
        do {
            let data = try JSONEncoder().encode(self)
            guard let dict = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: String] else {
                return nil
            }
            return dict
        } catch {
            DLLog("BaseHeader编码失败: \(error)")
            return nil
        }
    }
}

struct NetworkConfig: ApiConfiguration {
    var interceptor: RequestInterceptor?
    #if DEBUG
    var isDebugLogEnabled: Bool = true
    #else
    var isDebugLogEnabled: Bool = false
    #endif
    var baseURL: URL
    var commonHeaders: [String : String]
    var commonParameters: [String: Sendable] = [:]
    var timeout: TimeInterval = 50
    var decrypter: ApiDecrypter? = nil
}

@MainActor
@Observable
final class AppContainer {
    
    let authManager: AuthManager
    let userManager: UserManager
    let billingManager: BillingManager
    let deviceManager: DeviceManager
    private let agentCredentialStore: AppCredentialStore
    
    private let baseHeaders: [String: String]
    private(set) var apiProvider: ApiProvider?
    
    let environmentManager: EnvironmentManager
    
    /// AgentKit 用户身份管理 —— 登录 / Token 刷新 / 登出。
    let agentManager: AgentManager

    /// AgentKit 模型管理 —— 模型列表 + 本地偏好。
    let modelSettings: ModelSettingsStore

    /// 客户端工具注册表 — 注册本地可执行工具。
    let toolRegistry: ToolRegistry

    /// Product-specific additions to AgentKit's otherwise generic Timeline.
    let timelineExtensions: [any TimelineExtension]

    /// Deep link: set by `TalkifyApp.handleDeepLink`, consumed by `ChatRootViewController`
    /// to open WorkspaceBrowser directly at a specific workspace.
    var pendingDeepLinkWorkspacePath: String?

    /// Host-owned system notification and notification-click routing state.
    let conversationNotifications: ConversationNotificationCoordinator

    /// AgentKit host bridges for private Gateway-managed user images.
    let userAssetPicker: TalkifyUserAssetPicker
    let userAssetUploader: TalkifyUserAssetUploader
    let userAssetPreviewResolver: TalkifyUserAssetPreviewResolver
    let localUserAssetStager: TalkifyWorkspaceLocalAssetStager
    let localUserAssetPreviewResolver: TalkifyLocalUserAssetPreviewResolver
    private let userAssetFileStore: ManagedUserAssetFileStore
    private let userAssetLocalStateStore: ManagedUserAssetLocalStateStore

    init(authManager: AuthManager,
         environmentManager: EnvironmentManager,
         deviceManager: DeviceManager
    ) {

        self.authManager = authManager
        self.environmentManager = environmentManager
        self.deviceManager = deviceManager
        self.agentCredentialStore = AppCredentialStore(authManager: authManager)
        
        // 缓存基础头（仅创建一次，提升性能）
        do {
            let deviceInfo = try deviceManager.getDeviceInfo()
            self.baseHeaders = BaseHeader(deviceInfo: deviceInfo).toDictionary() ?? [:]
        } catch {
            self.baseHeaders = ["Content-Type": "application/json"]
            DLLog("⚠️ 设备信息获取失败：\(error)")
        }
        
        let apiProvider = Self.makeAuthorizedApiProvider(
            authManager: authManager,
            environmentConfig: environmentManager.currentConfig,
            commonHeaders: baseHeaders
        )
        self.apiProvider = apiProvider

        #if !DEBUG
        precondition(
            environmentManager.currentConfig.apiBaseURL.scheme == "https",
            "Release builds require an HTTPS Gateway"
        )
        #endif
        let userAssetFileStore: ManagedUserAssetFileStore
        do {
            userAssetFileStore = try ManagedUserAssetFileStore()
        } catch {
            fatalError("Unable to initialize the managed user asset store")
        }
        self.userAssetFileStore = userAssetFileStore
        self.userAssetLocalStateStore = ManagedUserAssetLocalStateStore(fileStore: userAssetFileStore)
        let accountScope: @Sendable () -> String = { [authManager] in
            authManager.currentUserId.map(String.init) ?? "signed-out"
        }
        let userAssetAPI = UserAssetAPI(
            baseURL: environmentManager.currentConfig.apiBaseURL,
            authorization: authManager
        )
        self.userAssetPicker = TalkifyUserAssetPicker(
            fileStore: userAssetFileStore,
            normalizer: UserImageNormalizer(fileStore: userAssetFileStore),
            accountScope: accountScope
        )
        self.userAssetUploader = TalkifyUserAssetUploader(
            normalizer: UserImageNormalizer(fileStore: userAssetFileStore),
            api: userAssetAPI,
            accountScope: accountScope
        )
        self.userAssetPreviewResolver = TalkifyUserAssetPreviewResolver(
            api: userAssetAPI,
            accountScope: accountScope
        )
        self.localUserAssetStager = TalkifyWorkspaceLocalAssetStager(
            fileStore: userAssetFileStore,
            normalizer: UserImageNormalizer(fileStore: userAssetFileStore)
        )
        self.localUserAssetPreviewResolver = TalkifyLocalUserAssetPreviewResolver()
        self.userManager = UserManager(
            service: UserService(apiProvider: apiProvider),
            environment: environmentManager.currentEnvironmentSnapshot
        )
        self.billingManager = BillingManager(service: BillingService(apiProvider: apiProvider))
        // AgentKit 账户与用量服务复用 Talkify 的授权 API Provider。
        self.agentManager = AgentManager(apiProvider: apiProvider)

        // ModelSettingsStore 通过 GatewayService 主动获取模型列表。
        // agentManager 实现 GatewayService 协议，提供 Gateway API 访问。
        self.modelSettings = ModelSettingsStore(service: agentManager)

        self.toolRegistry = ToolRegistry()
        self.conversationNotifications = ConversationNotificationCoordinator()

        #if os(macOS)
        self.timelineExtensions = [DesktopControlEvidenceTimeline()]
        #else
        self.timelineExtensions = []
        #endif

        // 注入 AgentKit 全局凭证存储：基于 AuthManager，不写 Keychain
        CredentialSettings.store = agentCredentialStore

        // 从旧 AgentSettings 迁移到新 CredentialStore（仅一次）
        CredentialSettings.migrateFromLegacyIfNeeded()

        // P1: 注册客户端工具（Go 服务端无法执行的本地工具）
        registerClientTools()

        // 通过 ModelSettingsStore 从 Gateway 获取模型列表
        Task {
            await modelSettings.refreshModels()
        }
        Task.detached(priority: .utility) { [userAssetFileStore] in
            userAssetFileStore.removeExpiredFiles()
        }
    }

    private func registerClientTools() {
        Task {
            await toolRegistry.register(DeviceInfoTool())
            await toolRegistry.register(CameraCaptureTool())
            await toolRegistry.register(DownloadFileTool())
            await toolRegistry.register(AnalyzeLocalImageTool())
            await toolRegistry.register(ReadPDFTool())
            await toolRegistry.register(RenderPDFPagesTool())
            await toolRegistry.register(RecordAudioTool())
            await toolRegistry.register(TranscribeAudioTool())
            await toolRegistry.register(ExtractArchiveTool())
#if os(iOS)
            await toolRegistry.register(ScanDocumentTool())
#endif
#if os(macOS)
            await toolRegistry.register(ScreenshotTool())
#endif
        }
    }

    func makeAgentClient() -> RuntimeClient {
        #if os(iOS)
        // iOS: 客户端只持有动态 RuntimeEnvironment。Runtime 的启动必须由稳定的
        // lifecycle 入口显式 await，不能在 SwiftUI body 构建依赖时产生副作用。
        return DefaultAgentClient.fromRuntime(credentialStore: agentCredentialStore)
        #else
        // macOS: 连接独立运行的 Talkify Agent runtime（127.0.0.1:8797）。
        let env = RuntimeEnvironment(host: "127.0.0.1", port: 8797)
        return DefaultAgentClient(environment: env, credentialStore: agentCredentialStore)
        #endif
    }

    func makeAgentDependencies() -> AgentDependencies {
        let credentialStore = agentCredentialStore
        return AgentDependencies(
            client: makeAgentClient(),
            toolRegistry: toolRegistry,
            timelineExtensions: timelineExtensions,
            conversationRendererMode: .web,
            onAuthExpired: { [credentialStore] in
                // iOS: runtime 收到 401 → 用最新凭证热重载
                // macOS: Token 刷新由 AuthManager 的 Alamofire RequestInterceptor 自动处理，
                //        CredentialStore 每次请求实时读取 authManager.token，无需手动重载。
                #if os(iOS)
                try? await AgentRuntime.shared.reconfigure(with: credentialStore)
                #endif
            },
            localStateStore: userAssetLocalStateStore,
            userAssetPicker: { [userAssetPicker] in
                try await userAssetPicker.pick()
            },
            localUserAssetStager: localUserAssetStager,
            userAssetUploader: userAssetUploader,
            userAssetPreviewResolver: userAssetPreviewResolver,
            localUserAssetPreviewResolver: localUserAssetPreviewResolver,
            onAttentionEvent: { [conversationNotifications] event in
                conversationNotifications.handle(event)
            }
        )
    }

    // MARK: - Credential Injection (iOS)

    func ensureAgentRuntimeStarted() async {
        #if os(iOS)
        _ = try? await AgentRuntime.shared.ensureStarted(
            with: agentCredentialStore
        )
        #endif
    }
    
    private static func makeAuthorizedApiProvider(
        authManager: AuthManager,
        environmentConfig: AppEnvironmentConfig,
        commonHeaders: [String: String]
    ) -> ApiProvider {
        let authInterceptor = AuthInterceptor(authManager: authManager)
        let mainConfig = NetworkConfig(
            interceptor: authInterceptor,
            baseURL: environmentConfig.apiBaseURL,
            commonHeaders: commonHeaders
        )
        return ApiProvider(config: mainConfig)
    }
    
    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(
            service: makeAuthService(),
            manager: authManager,
            userManager: userManager,
            environment: environmentManager.currentEnvironmentSnapshot
        )
    }
    
    
    func makeAuthService() -> AuthService {
        AuthService(api: makeApiProvider())
    }

    func makeBillingService() -> BillingService {
        BillingService(apiProvider: makeApiProvider())
    }
    
    // MARK: - ApiProvider 工厂方法（按需创建）
    func makeApiProvider() -> ApiProvider {
        if let apiProvider {
            return apiProvider
        }
        let apiProvider = Self.makeAuthorizedApiProvider(
            authManager: authManager,
            environmentConfig: environmentManager.currentConfig,
            commonHeaders: baseHeaders
        )
        self.apiProvider = apiProvider
        return apiProvider
    }
    
    // MARK: - Factory

    static func makeWorkspaceStore(dependencies: AgentDependencies) -> WorkspaceStore {
        WorkspaceStore(dependencies: dependencies)
    }
}

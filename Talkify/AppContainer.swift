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
    let providerConnections: ProviderConnectionStore
    private let providerConfigurationQueue = RuntimeProviderConfigurationApplyQueue()
    private var providerConfigurationApplyTask: Task<Void, Never>?
    
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

        // The Composer is driven exclusively by the unified multi-connection catalog.
        self.modelSettings = ModelSettingsStore()
        self.providerConnections = ProviderConnectionStore(
            modelSettings: modelSettings,
            gatewayCredentialStore: agentCredentialStore
        )

        self.toolRegistry = ToolRegistry()
        self.conversationNotifications = ConversationNotificationCoordinator()

        #if os(macOS)
        self.timelineExtensions = [DesktopControlEvidenceTimeline()]
        #else
        self.timelineExtensions = []
        #endif

        // Runtime receives Gateway credentials from AuthManager and direct-provider
        // credentials from the AgentKit Keychain store.
        CredentialSettings.store = providerConnections.credentialStore

        // P1: 注册客户端工具（Go 服务端无法执行的本地工具）
        registerClientTools()

        providerConnections.onStructuralChange = { [weak self] in
            self?.stageProviderConfigurationApply()
        }
        migrateLegacyProviderState()
        synchronizeGatewayConnectionWithIdentity()
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
            
            await toolRegistry.register(CreatePDFTool())
            await toolRegistry.register(MergePDFsTool())
            await toolRegistry.register(SplitPDFTool())
#if os(iOS)
            await toolRegistry.register(ScanDocumentTool())
#endif
#if os(macOS)
            await toolRegistry.register(ScreenshotTool())
#endif
        }
    }

    func makeAgentClient() -> RuntimeClient {
        #if os(iOS) || os(macOS)
        // Apple app hosts use the in-process Runtime on an OS-assigned loopback port.
        // This local transport is intentionally independent from Talkify Gateway
        // credentials. Provider credentials are injected into AgentRuntime instead.
        return DefaultAgentClient.fromRuntime()
        #else
        // Unsupported embedded hosts may still connect to a separately managed server.
        let env = RuntimeEnvironment(host: "127.0.0.1", port: 8797)
        return DefaultAgentClient(environment: env, credentialStore: providerConnections.credentialStore)
        #endif
    }

    func makeAgentDependencies() -> AgentDependencies {
        let credentialStore = providerConnections.credentialStore
        return AgentDependencies(
            client: makeAgentClient(),
            toolRegistry: toolRegistry,
            timelineExtensions: timelineExtensions,
            conversationRendererMode: .web,
            onAuthExpired: { [credentialStore] in
                // The embedded runtime owns its provider, so refresh its injected
                // credentials after either Apple host observes an auth expiry.
                #if os(iOS) || os(macOS)
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

    // MARK: - Embedded Runtime

    func ensureAgentRuntimeStarted() async {
        #if os(iOS) || os(macOS)
        do {
            if !AgentRuntime.shared.isAlive {
                var configuration = EmbeddedRuntimeConfiguration.platformDefault()
                #if os(macOS) && TALKIFY_MAC_APP_STORE
                configuration.profile = .sandboxed
                configuration.executableSearchPaths = []
                #elseif os(macOS) && TALKIFY_MAC_DIRECT
                configuration.profile = .fullDesktop
                #endif
                try AgentRuntime.shared.configure(configuration)
                try AgentRuntime.shared.configureProviderConnections(
                    makeRuntimeProviderConfiguration()
                )
            }
            _ = try await AgentRuntime.shared.ensureStarted(
                with: providerConnections.credentialStore
            )
        } catch {
            DLLog("⚠️ Agent Runtime 启动失败：\(error)")
        }
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

    // MARK: - Provider Connections

    func requestGatewayConnection() {
        authManager.showLoginSheet = true
    }

    func synchronizeGatewayConnectionWithIdentity() {
        guard authManager.isRegistered else {
            if providerConnections.gatewayConnection != nil {
                providerConnections.removeGatewayConnection()
            }
            clearGatewayAccountCaches()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await refreshGatewayConnection()
        }
    }

    func disconnectGateway() async {
        if authManager.isRegistered {
            try? await makeAuthService().logout()
        }
        authManager.logout()
        providerConnections.removeGatewayConnection()
        clearGatewayAccountCaches()
        await userAssetPreviewResolver.clearCache()
    }

    func refreshGatewayConnection() async {
        guard authManager.isRegistered else { return }
        do {
            let response = try await agentManager.fetchModels()
            let models = response.models
                .filter { $0.available != false }
                .map(Self.providerModel)
            try providerConnections.upsertGateway(
                baseURL: gatewayAgentBaseURL,
                models: models,
                allowsInsecurePrivateNetworkHTTP: allowsLocalGatewayHTTP
            )
            if let descriptor = providerConnections.catalog.models.first(where: {
                $0.connectionID == ProviderConnection.talkifyGatewayID
                    && $0.wireModelID == response.defaultModel
            }) {
                providerConnections.setDefaultModel(descriptor.id)
            }
            await userManager.refreshProfileIfNeeded(maxAge: 0)
            await billingManager.refreshAllIfNeeded(maxAge: 0)
            agentManager.fetchUsage()
        } catch {
            DLLog("⚠️ Gateway Provider 刷新失败：\(error)")
        }
    }

    private func clearGatewayAccountCaches() {
        userManager.clear()
        billingManager.clear()
        agentManager.clear()
    }

    private static func providerModel(_ model: GatewayModel) -> ProviderModel {
        let category = model.category?.lowercased() ?? ""
        return ProviderModel(
            id: model.id,
            displayName: model.displayName,
            contextWindow: model.contextWindow,
            supportsTools: model.supportsToolCalls ?? true,
            supportsReasoning: category.contains("reason") || category.contains("think")
        )
    }

    private func makeRuntimeProviderConfiguration() throws -> GeneratedRuntimeProviderConfiguration {
        let connections = providerConnections.registry.enabledConnections
        guard !connections.unifiedModels.isEmpty else {
            return try RuntimeProviderConfigurationBuilder.buildEmpty()
        }
        return try RuntimeProviderConfigurationBuilder.build(
            connections: connections,
            defaultModelID: providerConnections.catalog.defaultModelID
        )
    }

    private func stageProviderConfigurationApply() {
        guard let generated = try? makeRuntimeProviderConfiguration() else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = await providerConfigurationQueue.stage(generated)
            beginProviderConfigurationApplyLoopIfNeeded()
        }
    }

    private func beginProviderConfigurationApplyLoopIfNeeded() {
        guard providerConfigurationApplyTask == nil else { return }
        providerConfigurationApplyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { providerConfigurationApplyTask = nil }

            while !Task.isCancelled {
                guard AgentRuntime.shared.isAlive else {
                    let emptySnapshot = RuntimeActivitySnapshot(
                        cursor: 0,
                        sessions: []
                    )
                    if let staged = await providerConfigurationQueue
                        .configurationIfRuntimeIdle(emptySnapshot) {
                        do {
                            try AgentRuntime.shared.configureProviderConnections(staged.configuration)
                            await providerConfigurationQueue.markApplied(revision: staged.revision)
                        } catch {
                            DLLog("⚠️ Provider 配置暂存失败：\(error)")
                        }
                    }
                    return
                }

                guard let snapshot = try? await makeAgentClient().activitySnapshot(),
                      let staged = await providerConfigurationQueue
                        .configurationIfRuntimeIdle(snapshot) else {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }

                do {
                    AgentRuntime.shared.stop()
                    try AgentRuntime.shared.configureProviderConnections(staged.configuration)
                    _ = try await AgentRuntime.shared.ensureStarted(
                        with: providerConnections.credentialStore
                    )
                    await providerConfigurationQueue.markApplied(revision: staged.revision)
                } catch {
                    DLLog("⚠️ Provider 配置应用失败：\(error)")
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func migrateLegacyProviderState() {
        if authManager.isRegistered, providerConnections.gatewayConnection == nil {
            try? providerConnections.upsertGateway(
                baseURL: gatewayAgentBaseURL,
                models: [],
                allowsInsecurePrivateNetworkHTTP: allowsLocalGatewayHTTP
            )
        }

        let migrationKey = "talkify.provider-connections.legacy-key.v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey),
              providerConnections.registry.connection(id: "deepseek") == nil else {
            return
        }
        let legacyKey = AgentSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacyKey.isEmpty,
              let template = TalkifyProviderTemplate.builtIn.first(where: { $0.id == "deepseek" }),
              let baseURL = template.baseURL else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        let connection = ProviderConnection(
            id: "deepseek",
            providerID: template.id,
            displayName: template.displayName,
            transport: .openAIChatCompletions,
            authentication: .apiKey,
            baseURL: baseURL,
            models: template.models
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                try await providerConnections.save(
                    connection,
                    apiKey: legacyKey,
                    isNew: true
                )
                UserDefaults.standard.set(true, forKey: migrationKey)
            } catch {
                DLLog("⚠️ 旧 DeepSeek 凭证迁移失败：\(error)")
            }
        }
    }

    private var gatewayAgentBaseURL: URL {
        environmentManager.currentConfig.apiBaseURL.appendingPathComponent("agent")
    }

    private var allowsLocalGatewayHTTP: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
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

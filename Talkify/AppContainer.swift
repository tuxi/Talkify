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
    let runtimeServers: RuntimeServerCoordinator
    #if os(macOS)
    let sharingController: RuntimeSharingController
    #endif

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
        self.runtimeServers = RuntimeServerCoordinator()
        #if os(macOS)
        self.sharingController = RuntimeSharingController()
        #endif

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

        // C2.3: AgentKit A2.3 删除了旧 env-name secretsJSON 通道
        // （AgentSettings.secretsJSON()）。`CredentialSettings.migrateFromLegacyIfNeeded()`
        // 在 AgentKit 内部没有调用点，宿主启动路径必须显式调用，否则旧
        // AgentSettings.apiKey Keychain 值不会迁入 CredentialMap，注入将收到 "{}"。
        // 必须先设置 store（上一行），迁移才会写入宿主 Keychain。
        CredentialSettings.migrateFromLegacyIfNeeded()

        // P1: 注册客户端工具（Go 服务端无法执行的本地工具）
        registerClientTools()

        // Provider definitions now flow over HTTP /v1/providers. When the runtime
        // returns `applied == false` (persisted, restart required), the embedded
        // runtime is restarted in place so the change takes effect immediately.
        providerConnections.onRuntimeRestartNeeded = { [weak self] in
            guard let self else { return }
            #if canImport(CodeAgentRuntime)
            do {
                AgentRuntime.shared.stop()
                _ = try await AgentRuntime.shared.ensureStarted(
                    with: providerConnections.credentialStore
                )
                runtimeServers.embeddedStatusMonitor.markConnected()
                await refreshActiveRuntimeContext()
            } catch {
                DLLog("⚠️ embedded runtime 重启失败：\(error)")
            }
            #endif
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
            await toolRegistry.register(ExtractVideoFramesTool())
#if os(iOS)
            await toolRegistry.register(ScanDocumentTool())
#endif
#if os(macOS)
            await toolRegistry.register(ScreenshotTool())
#endif
        }
    }

    func makeAgentClient() -> any RuntimeClient {
        #if os(iOS) || os(macOS)
        do {
            return try runtimeServers.makeActiveClient()
        } catch {
            preconditionFailure("Invalid active Runtime Server: \(error)")
        }
        #else
        // Unsupported embedded hosts may still connect to a separately managed server.
        let env = RuntimeEnvironment(host: "127.0.0.1", port: 8797)
        return DefaultAgentClient(environment: env, credentialStore: providerConnections.credentialStore)
        #endif
    }

    func makeAgentDependencies() -> AgentDependencies {
        let serverConnectionID = runtimeServers.activeConnectionID
        return AgentDependencies(
            client: makeAgentClient(),
            toolRegistry: toolRegistry,
            timelineExtensions: timelineExtensions,
            conversationRendererMode: .web,
            onAuthExpired: { [weak self] in
                // The runtime resolves the gateway provider from the injected
                // gateway/default credential. Re-push the refreshed token over
                // /v1/secrets so the next turn uses it without a restart.
                guard let self else { return }
                await providerConnections.pushGatewayCredentialToRuntime()
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
                conversationNotifications.handle(
                    event,
                    serverConnectionID: serverConnectionID
                )
            }
        )
    }

    // MARK: - Embedded Runtime

    func ensureAgentRuntimeStarted() async {
        #if os(macOS)
        // macOS (Direct + App Store): launch codeagentd as a standalone daemon.
        // The daemon reads ~/.codeagent/settings.json (shared with CLI) and
        // inherits a login-shell PATH — no hardcoded PATH hacks needed.
        await ensureDaemonStarted()
        #elseif os(iOS)
        // iOS: use the embedded gomobile runtime (only option on iOS).
        guard runtimeServers.activeConnection.kind == .embedded else {
            await refreshActiveRuntimeContext()
            return
        }
        await ensureEmbeddedRuntimeStarted()
        #endif
    }

    #if os(macOS)
    /// Launch codeagentd, register it as a local RuntimeServerConnection,
    /// and set it as the active server.
    ///
    /// On failure the daemon is retried once; if it still fails the embedded
    /// runtime is used as a last-resort fallback. The active connection is
    /// logged prominently so you always know which backend is serving requests.
    private func ensureDaemonStarted() async {
        let daemon = CodeAgentDaemon.shared
        if !daemon.isRunning {
            // One-shot retry for transient failures (e.g. port-file race).
            for attempt in 1...2 {
                do {
                    try daemon.start()
                    try await daemon.waitForReady(timeout: 10.0)

                    guard let endpoint = daemon.endpoint else {
                        throw CodeAgentDaemonError.portNotResolved
                    }
                    let connection = try RuntimeServerConnection.external(
                        id: "talkify-local-daemon",
                        displayName: "本地 CodeAgent 服务",
                        endpoint: endpoint,
                        authentication: .bearer,
                        platform: .macOS
                    )
                    // If a stale daemon record from an earlier launch is still
                    // the active connection, switch away first so we can remove it.
                    if runtimeServers.registry.activeConnectionID == connection.id {
                        _ = try? runtimeServers.registry.setActive(
                            connectionID: RuntimeServerConnection.embeddedID
                        )
                    }
                    _ = try? runtimeServers.registry.remove(
                        connectionID: connection.id
                    )
                    try runtimeServers.registry.upsert(connection)
                    try runtimeServers.registry.setActive(connectionID: connection.id)
                    try await runtimeServers.injectBearerToken(
                        for: connection.id,
                        token: daemon.accessToken
                    )

                    DLLog("✅ [RUNTIME] 活跃后端：codeagentd daemon (port \(daemon.port), pid \(daemon.processID))")

                    // Stage ③: install the desktop provider store via AgentKit.
                    // On the desktop path the local registry becomes a read-only
                    // cache and provider definitions are managed through the
                    // runtime's /v1/providers API.
                    if let providerStore = try? runtimeServers.makeProviderStore() {
                        providerConnections.providerStore = providerStore
                        // One-time migration: UserDefaults connections → runtime.
                        await providerConnections.migrateToRuntimeProviderManagementIfNeeded(
                            store: providerStore
                        )
                    }

                    // A2 secrets push: push the Keychain llm credentials over
                    // /v1/secrets so the runtime's injected resolver has them and
                    // GET /v1/runtime/models reports available=true without restart.
                    providerConnections.onSecretsPushed = { [weak self] in
                        Task { await self?.refreshActiveRuntimeContext() }
                    }
                    await providerConnections.pushLLMCredentialsToDaemon()
                    // Shared file: also write ~/.codeagent/secrets.json so
                    // the runtime CLI/TUI (separate process) reuses the keys.
                    await providerConnections.writeSharedSecretsFile()

                    await refreshActiveRuntimeContext()
                    return
                } catch {
                    DLLog("⚠️ [RUNTIME] daemon 启动失败 (attempt \(attempt)/2): \(error)")
                    daemon.stop()
                    if attempt < 2 { try? await Task.sleep(for: .milliseconds(500)) }
                }
            }

            // Daemon failed after retries — keep it set as active but
            // mark it offline. The user can retry via Runtime Server settings.
            DLLog("⚠️ [RUNTIME] daemon 彻底失败，请在设置中重试或手动添加服务")
            _ = try? runtimeServers.registry.setActive(
                connectionID: RuntimeServerConnection.embeddedID
            )
            return
        }
        await refreshActiveRuntimeContext()
    }

    func stopDaemonIfNeeded() {
        CodeAgentDaemon.shared.stop()
    }
    #endif

    private func ensureEmbeddedRuntimeStarted() async {
        #if os(iOS)
        do {
            if !AgentRuntime.shared.isAlive {
                var configuration = EmbeddedRuntimeConfiguration.platformDefault()
                try AgentRuntime.shared.configure(configuration)
            }
            _ = try await AgentRuntime.shared.ensureStarted(
                with: providerConnections.credentialStore
            )
            // Provider management is now HTTP-backed on iOS too: the embedded
            // runtime persists providers to <DataDir>/.codeagent/settings.json
            // and exposes /v1/providers + /v1/secrets exactly like the daemon.
            // Install the HTTP provider store (mirrors ensureDaemonStarted) and
            // migrate any pre-existing UserDefaults connections once.
            if providerConnections.providerStore == nil {
                if let providerStore = try? runtimeServers.makeProviderStore() {
                    providerConnections.providerStore = providerStore
                    await providerConnections.migrateToRuntimeProviderManagementIfNeeded(
                        store: providerStore
                    )
                }
            }
            // A2 secrets push: push the Keychain llm credentials over /v1/secrets
            // so GET /v1/runtime/models reports available=true without a restart.
            await providerConnections.pushLLMCredentialsToDaemon()
            runtimeServers.embeddedStatusMonitor.markConnected()
            await refreshActiveRuntimeContext()
        } catch {
            DLLog("⚠️ Agent Runtime 启动失败：\(error)")
        }
        #endif
    }

    func refreshActiveRuntimeContext() async {
        do {
            await providerConnections.refreshCacheFromRuntime()
            let context = try await runtimeServers.refreshActiveContext()
            publishRuntimeServerModels(context)
        } catch {
            modelSettings.applyUnifiedCatalog([], defaultModelID: nil)
            DLLog("⚠️ 当前 Runtime Server 上下文刷新失败：\(error)")
        }
    }

    func activateRuntimeServer(
        connectionID: String,
        allowingActiveWorkInterruption: Bool = false
    ) async throws {
        #if os(iOS)
        if connectionID == RuntimeServerConnection.embeddedID {
            await ensureEmbeddedRuntimeStarted()
        }
        #endif
        let context = try await runtimeServers.activate(
            connectionID: connectionID,
            allowingActiveWorkInterruption: allowingActiveWorkInterruption
        )
        publishRuntimeServerModels(context)
    }

    private func publishRuntimeServerModels(
        _ context: RuntimeServerActiveContext
    ) {
        // v2 catalog fix: context.models may be empty; extract from modelCatalog.connections
        let models: [UnifiedModelDescriptor] = context.modelCatalog.connections.flatMap { connection in
            connection.models.compactMap { (model: RuntimeServerModelDescriptor) -> UnifiedModelDescriptor? in
                guard model.available else { return nil }
                let modalities = Set(
                    model.inputModalities.compactMap(ProviderInputModality.init(rawValue:))
                )
                return UnifiedModelDescriptor(
                    serverConnectionID: context.serverConnectionID,
                    connectionID: connection.id,
                    providerID: connection.providerID,
                    providerDisplayName: connection.displayName,
                    runtimeAlias: model.runtimeAlias,
                    wireModelID: model.wireModelID,
                    displayName: model.displayName,
                    contextWindow: model.contextWindow,
                    supportsTools: model.supportsTools,
                    supportsReasoning: model.supportsReasoning,
                    inputModalities: modalities.isEmpty ? [.text] : modalities,
                    billingSource: connection.billingSource
                )
            }
        }
        
        // v2 catalog: defaultRuntimeAlias in modelCatalog, fallback to context.defaultModelID
        let defaultModelID = context.modelCatalog.defaultRuntimeAlias.isEmpty
            ? context.defaultModelID
            : context.modelCatalog.defaultRuntimeAlias
        
        modelSettings.applyUnifiedCatalog(
            models,
            defaultModelID: defaultModelID
        )
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
                Task { await providerConnections.removeGatewayConnection() }
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
        await providerConnections.removeGatewayConnection()
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
            try await providerConnections.upsertGateway(
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

    private func migrateLegacyProviderState() {
        if authManager.isRegistered, providerConnections.gatewayConnection == nil {
            Task { [weak self] in
                guard let self else { return }
                try? await providerConnections.upsertGateway(
                    baseURL: gatewayAgentBaseURL,
                    models: [],
                    allowsInsecurePrivateNetworkHTTP: allowsLocalGatewayHTTP
                )
            }
        }

        let migrationKey = "talkify.provider-connections.legacy-key.v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey),
              providerConnections.registry.connection(id: "deepseek") == nil else {
            return
        }
        let legacyKey = AgentSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacyKey.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        let deepseekBaseURL = URL(string: "https://api.deepseek.com")!
        let deepseekModels: [ProviderModel] = [
            ProviderModel(id: "deepseek-v4-flash", runtimeAlias: "deepseek", contextWindow: 1_000_000, supportsTools: true, supportsReasoning: true, inputPricePerMillion: 0.16, outputPricePerMillion: 0.32, webSearch: true),
            ProviderModel(id: "deepseek-v4-pro", runtimeAlias: "deepseek-pro", contextWindow: 1_000_000, supportsTools: true, supportsReasoning: true, inputPricePerMillion: 0.45, outputPricePerMillion: 0.90),
        ]
        let connection = ProviderConnection(
            id: "deepseek",
            providerID: "deepseek",
            displayName: "DeepSeek",
            transport: .openAIChatCompletions,
            authentication: .apiKey,
            baseURL: deepseekBaseURL,
            models: deepseekModels
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

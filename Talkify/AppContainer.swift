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

private struct PendingProviderConfiguration {
    let generated: GeneratedRuntimeProviderConfiguration
    let catalog: ProviderCatalogSnapshot
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
    private let providerConfigurationQueue = RuntimeProviderConfigurationApplyQueue()
    private var desiredProviderConfiguration: PendingProviderConfiguration?
    private var providerCatalogsByRevision: [UInt64: ProviderCatalogSnapshot] = [:]
    private var configuredProviderCatalogAwaitingRuntimeStart: ProviderCatalogSnapshot?
    private var providerConfigurationStageTask: Task<Void, Never>?
    private var providerConfigurationApplyTask: Task<Void, Never>?
    private var lastProviderConfigurationBlockerLog: String?
    
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

    func makeAgentClient() -> any RuntimeClient {
        #if os(iOS) || os(macOS)
        // Phase A exposes only the reserved Embedded connection. Phase C extends
        // RuntimeServerCoordinator without changing this host construction path.
        do {
            return try runtimeServers.makeActiveClient()
        } catch {
            preconditionFailure("Invalid active Runtime Server in Phase A: \(error)")
        }
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
                configuredProviderCatalogAwaitingRuntimeStart =
                    providerConnections.catalogSnapshot()
            }
            _ = try await AgentRuntime.shared.ensureStarted(
                with: providerConnections.credentialStore
            )
            runtimeServers.embeddedStatusMonitor.markConnected()
            let queuedRevision = await providerConfigurationQueue.pendingRevision()
            if desiredProviderConfiguration == nil,
               queuedRevision == nil,
               let catalogToPublish = configuredProviderCatalogAwaitingRuntimeStart {
                providerConnections.publishAppliedCatalog(
                    catalogToPublish,
                    hasPendingConfiguration: false
                )
                configuredProviderCatalogAwaitingRuntimeStart = nil
            } else if queuedRevision != nil {
                beginProviderConfigurationApplyLoopIfNeeded()
            }
        } catch {
            DLLog("⚠️ Agent Runtime 启动失败：\(error)")
            providerConnections.markRuntimeConfigurationFailed(error)
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
        providerConnections.markRuntimeConfigurationPending()
        do {
            desiredProviderConfiguration = PendingProviderConfiguration(
                generated: try makeRuntimeProviderConfiguration(),
                catalog: providerConnections.catalogSnapshot()
            )
            beginProviderConfigurationStageLoopIfNeeded()
        } catch {
            providerConnections.markRuntimeConfigurationFailed(error)
            DLLog("⚠️ Provider 配置生成失败：\(error)")
        }
    }

    private func beginProviderConfigurationStageLoopIfNeeded() {
        guard providerConfigurationStageTask == nil else { return }
        providerConfigurationStageTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let desired = desiredProviderConfiguration {
                desiredProviderConfiguration = nil
                let revision = await providerConfigurationQueue.stage(desired.generated)
                providerCatalogsByRevision[revision] = desired.catalog
                DLLog(
                    "Provider 配置已排队：revision=\(revision)，models=\(desired.catalog.models.count)"
                )
                beginProviderConfigurationApplyLoopIfNeeded()
            }
            providerConfigurationStageTask = nil
        }
    }

    private func beginProviderConfigurationApplyLoopIfNeeded() {
        guard providerConfigurationApplyTask == nil else { return }
        providerConfigurationApplyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await runProviderConfigurationApplyLoop()
            providerConfigurationApplyTask = nil

            // A stage can land while the loop is awaiting its final pending check.
            // Re-check after clearing the task so that change cannot lose its wake-up.
            if await providerConfigurationQueue.pendingRevision() != nil {
                beginProviderConfigurationApplyLoopIfNeeded()
            }
        }
    }

    private func runProviderConfigurationApplyLoop() async {
        while !Task.isCancelled {
            guard await providerConfigurationQueue.pendingRevision() != nil else {
                return
            }

            let activitySnapshot: RuntimeActivitySnapshot
            if AgentRuntime.shared.isAlive {
                do {
                    activitySnapshot = try await makeAgentClient().activitySnapshot()
                } catch {
                    providerConnections.markRuntimeConfigurationFailed(error)
                    DLLog("⚠️ Provider 配置等待 Runtime 空闲失败：\(error)")
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
            } else {
                activitySnapshot = RuntimeActivitySnapshot(cursor: 0, sessions: [])
            }

            let blockingDescriptions = ProviderRuntimeActivityPolicy.blockingDescriptions(
                in: activitySnapshot
            )
            if !blockingDescriptions.isEmpty {
                let summary = blockingDescriptions.joined(separator: "; ")
                providerConnections.markRuntimeConfigurationWaiting(
                    "正在等待 \(blockingDescriptions.count) 个会话结束。"
                )
                if summary != lastProviderConfigurationBlockerLog {
                    lastProviderConfigurationBlockerLog = summary
                    DLLog("Provider 配置等待 Runtime 空闲：\(summary)")
                }
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            lastProviderConfigurationBlockerLog = nil
            providerConnections.markRuntimeConfigurationWaiting(nil)

            // Code-Agent 1.2.1 serializes an idle queue position as `0`.
            // AgentKit's current queue helper treats every non-nil position as
            // active, so pass an explicit idle snapshot after the host has
            // applied the protocol-correct `position > 0` policy above.
            let idleSnapshot = RuntimeActivitySnapshot(
                generatedAt: activitySnapshot.generatedAt,
                cursor: activitySnapshot.cursor,
                isDelta: activitySnapshot.isDelta,
                sessions: []
            )
            guard let staged = await providerConfigurationQueue
                .configurationIfRuntimeIdle(idleSnapshot) else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            do {
                if AgentRuntime.shared.isAlive {
                    AgentRuntime.shared.stop()
                    try AgentRuntime.shared.configureProviderConnections(staged.configuration)
                    _ = try await AgentRuntime.shared.ensureStarted(
                        with: providerConnections.credentialStore
                    )
                    runtimeServers.embeddedStatusMonitor.markConnected()
                    await finishApplyingProviderConfiguration(staged)
                } else {
                    // Runtime startup owns the final start and catalog publication.
                    // Installing the YAML here keeps a pre-start registry mutation,
                    // but does not expose its aliases to Composer prematurely.
                    try AgentRuntime.shared.configureProviderConnections(staged.configuration)
                    configuredProviderCatalogAwaitingRuntimeStart =
                        providerCatalogsByRevision[staged.revision]
                    await providerConfigurationQueue.markApplied(revision: staged.revision)
                    providerCatalogsByRevision.removeValue(forKey: staged.revision)
                    providerCatalogsByRevision = providerCatalogsByRevision.filter {
                        $0.key > staged.revision
                    }
                    DLLog(
                        "Provider 配置已写入待启动 Runtime：revision=\(staged.revision)"
                    )
                    return
                }
            } catch {
                providerConnections.markRuntimeConfigurationFailed(error)
                DLLog("⚠️ Provider 配置应用失败：\(error)")
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func finishApplyingProviderConfiguration(
        _ staged: StagedRuntimeProviderConfiguration
    ) async {
        await providerConfigurationQueue.markApplied(revision: staged.revision)
        guard let catalog = providerCatalogsByRevision.removeValue(
            forKey: staged.revision
        ) else { return }

        let queuedRevision = await providerConfigurationQueue.pendingRevision()
        let hasPendingConfiguration =
            desiredProviderConfiguration != nil
            || queuedRevision != nil
        providerConnections.publishAppliedCatalog(
            catalog,
            hasPendingConfiguration: hasPendingConfiguration
        )
        configuredProviderCatalogAwaitingRuntimeStart = nil
        DLLog(
            "Provider 配置已生效：revision=\(staged.revision)，models=\(catalog.models.count)，hasPending=\(hasPendingConfiguration)"
        )

        if !hasPendingConfiguration {
            providerCatalogsByRevision = providerCatalogsByRevision.filter {
                $0.key > staged.revision
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

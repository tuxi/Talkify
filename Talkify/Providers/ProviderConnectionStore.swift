import Foundation
import AgentKit
import OSLog

private let providerStoreLogger = Logger(subsystem: "com.objc.chat", category: "ProviderStore")

struct ProviderCatalogSnapshot: Sendable {
    let models: [UnifiedModelDescriptor]
    let defaultModelID: String?
}

enum ProviderRuntimeActivityPolicy {
    static func blockingDescriptions(
        in snapshot: RuntimeActivitySnapshot
    ) -> [String] {
        snapshot.sessions.compactMap { activity in
            var reasons: [String] = []
            let state = activity.state.lowercased()
            // States that do not block a Runtime restart. `paused` means the
            // turn is suspended awaiting user input and will never resolve on
            // its own — treating it as blocking deadlocks the apply loop while
            // the user sees no actionable prompt. Unknown states intentionally
            // remain blocking (fail-closed).
            let nonBlockingStates: Set<String> = ["idle", "done", "failed", "cancelled", "paused"]

            if activity.effectiveActiveTurnID != nil,
               !nonBlockingStates.contains(state) {
                reasons.append("turn=\(activity.effectiveActiveTurnID ?? "-")")
            }
            if let position = activity.queuePosition, position > 0 {
                reasons.append("queue=\(position)")
            }
            if let count = activity.pendingApprovalCount, count > 0 {
                reasons.append("approvals=\(count)")
            }
            if let count = activity.pendingClientToolCount, count > 0 {
                reasons.append("clientTools=\(count)")
            }

            guard !reasons.isEmpty else { return nil }
            return "\(activity.sessionID){state=\(activity.state),\(reasons.joined(separator: ","))}"
        }
    }

    static func hasActiveRuntimeWork(_ snapshot: RuntimeActivitySnapshot) -> Bool {
        !blockingDescriptions(in: snapshot).isEmpty
    }
}

enum ProviderConnectionStoreError: Error, LocalizedError {
    case apiKeyRequired

    var errorDescription: String? {
        switch self {
        case .apiKeyRequired:
            "请输入 API 密钥。"
        }
    }
}

@MainActor
@Observable
final class ProviderConnectionStore {
    let registry: ProviderConnectionRegistry
    let catalog: UnifiedModelCatalogStore
    let credentialStore: CompositeCredentialStore
    let directCredentialStore: KeychainCredentialStore

    private let modelSettings: ModelSettingsStore
    var onStructuralChange: (() -> Void)?
    private(set) var isApplyingRuntimeConfiguration = false
    private(set) var runtimeConfigurationError: String?
    private(set) var runtimeConfigurationWaitDescription: String?

    /// Desktop provider store (AgentKit `any ProviderStore`). Non-nil only when
    /// connected to a codeagentd daemon (`.local`/`.remote` active runtime) —
    /// built via `RuntimeServerCoordinator.makeProviderStore()`.
    /// When set, provider definitions are managed via the runtime's /v1/providers
    /// and the local registry becomes a read-only cache. iOS embedded keeps nil
    /// and uses the local registry + injection path.
    var providerStore: (any ProviderStore)?

    /// Desktop daemon secrets client (POST /v1/secrets). Non-nil only when the
    /// codeagentd daemon is active. Pushes Keychain llm credentials into the
    /// daemon's injected resolver so GET /v1/runtime/models reports
    /// available=true without a restart.
    var secretsClient: RuntimeSecretsClient?

    /// Called after a successful secrets push — AppContainer uses it to
    /// re-GET /v1/runtime/models so the model list reflects available=true.
    var onSecretsPushed: (() -> Void)?

    /// Last secrets-push error, surfaced in the settings page (kept usable).
    private(set) var lastSecretsPushError: String?

    /// Last shared-secrets-file write error (~/.codeagent/secrets.json).
    private(set) var sharedSecretsFileError: String?

    /// Connection IDs whose PUT/DELETE returned `applied: false`
    /// ("persisted, restart required"). Shown in the settings page.
    private(set) var pendingRestartConnectionIDs: Set<String> = []

    /// Provider templates fetched from the runtime (GET /v1/provider-templates).
    /// Empty on iOS embedded (no server); the app falls back to the local
    /// "custom" template only.
    private(set) var providerTemplates: [RuntimeProviderTemplate] = []

    /// Templates converted to the chater presentation model, combining runtime
    /// templates with the local "custom" fallback.
    var talkifyTemplates: [TalkifyProviderTemplate] {
        TalkifyProviderTemplate.all(from: providerTemplates)
    }

    init(
        modelSettings: ModelSettingsStore,
        gatewayCredentialStore: any CredentialStore,
        defaults: UserDefaults = .standard
    ) {
        self.modelSettings = modelSettings
        self.registry = ProviderConnectionRegistry(defaults: defaults)
        self.catalog = UnifiedModelCatalogStore(defaults: defaults)
        self.directCredentialStore = KeychainCredentialStore(
            service: "com.objc.talkify.provider-credentials"
        )
        self.credentialStore = CompositeCredentialStore(
            storesByNamespace: [
                "gateway": gatewayCredentialStore,
                "llm": directCredentialStore,
            ]
        )
        reloadCatalog()
    }

    var connections: [ProviderConnection] { registry.connections }
    var enabledModels: [UnifiedModelDescriptor] { catalog.models }
    var hasAvailableModels: Bool { !enabledModels.isEmpty }
    var gatewayConnection: ProviderConnection? {
        registry.connection(id: ProviderConnection.talkifyGatewayID)
    }

    func credentialExists(for connection: ProviderConnection) -> Bool {
        guard let target = connection.credentialTarget else { return true }
        return credentialStore.resolveSync(target) != nil
    }

    func save(
        _ connection: ProviderConnection,
        apiKey: String?,
        isNew: Bool
    ) async throws {
        try connection.validate()
        if connection.authentication == .apiKey {
            let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                try await credentialStore.set(
                    Credential(kind: .bearer, secret: trimmed),
                    for: .llm(connection.id)
                )
                // A2 secrets push: re-push the changed target to the daemon so
                // the model becomes available without a restart. Idempotent.
                await pushLLMCredentialsToDaemon(only: .llm(connection.id))
                // Shared file: also refresh ~/.codeagent/secrets.json for the
                // runtime CLI/TUI (separate process). Mirrors the A2 timing.
                await writeSharedSecretsFile(only: .llm(connection.id))
            } else if isNew && directCredentialStore.resolveSync(.llm(connection.id)) == nil {
                throw ProviderConnectionStoreError.apiKeyRequired
            }
        }
        if let store = providerStore {
            // Desktop: definition over HTTP, credential value stays in Keychain.
            let result = try await store.upsertProvider(connection.asRuntimeProviderDefinition())
            if result.applied {
                pendingRestartConnectionIDs.remove(connection.id)
                await refreshCacheFromRuntime(store: store)
            } else {
                pendingRestartConnectionIDs.insert(connection.id)
            }
        } else {
            // iOS embedded (or daemon offline): local registry + injection.
            try registry.upsert(connection)
            didMutateRegistry()
        }
    }

    func remove(connectionID: String) async throws {
        guard let connection = registry.connection(id: connectionID) else {
            // Desktop cache may already be refreshed; allow delete anyway.
            if let store = providerStore {
                let result = try await store.deleteProvider(id: connectionID)
                if result.applied {
                    pendingRestartConnectionIDs.remove(connectionID)
                    await refreshCacheFromRuntime(store: store)
                } else {
                    pendingRestartConnectionIDs.insert(connectionID)
                }
            }
            return
        }
        
        
        
        if let store = providerStore {
            let result = try await store.deleteProvider(id: connectionID)
            if result.applied {
                pendingRestartConnectionIDs.remove(connectionID)
                await refreshCacheFromRuntime(store: store)
            } else {
                pendingRestartConnectionIDs.insert(connectionID)
            }
        }
        _ = registry.remove(connectionID: connectionID)
        didMutateRegistry()
        if connection.authentication == .apiKey {
            try await credentialStore.remove(.llm(connection.id))
        }
    }

    func setEnabled(_ enabled: Bool, connectionID: String) {
        if let store = providerStore {
            Task { @MainActor in
                guard var connection = registry.connection(id: connectionID) else { return }
                connection.isEnabled = enabled
                do {
                    let result = try await store.upsertProvider(connection.asRuntimeProviderDefinition())
                    if result.applied {
                        pendingRestartConnectionIDs.remove(connectionID)
                        await refreshCacheFromRuntime(store: store)
                    } else {
                        pendingRestartConnectionIDs.insert(connectionID)
                    }
                } catch {
                    runtimeConfigurationError = error.localizedDescription
                }
            }
        } else {
            registry.setEnabled(enabled, connectionID: connectionID)
            didMutateRegistry()
        }
    }

    /// Fetch provider templates from the runtime. No-op on iOS embedded.
    func loadProviderTemplates(store: (any ProviderStore)? = nil) async {
        guard let store = store ?? providerStore else { return }
        do {
            providerTemplates = try await store.listProviderTemplates()
        } catch {
            providerStoreLogger.error("加载 provider 模板失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rebuild the local registry cache from listProviders() (desktop).
    /// Also re-GETs /v1/runtime/models to refresh the model list.
    func refreshCacheFromRuntime(store: (any ProviderStore)? = nil) async {
        guard let store = store ?? providerStore else { return }
        do {
            let providers = try await store.listProviders()
            let connections = providers.map { $0.asProviderConnection() }
            try registry.replaceAll(connections)
            reloadCatalog()
            await loadProviderTemplates(store: store)
            onStructuralChange?()
        } catch {
            runtimeConfigurationError = error.localizedDescription
        }
    }

    /// One-time migration: existing UserDefaults connections → PUT to runtime
    /// (reuse buildConnectionsJSON mapping), then registry becomes a read-only
    /// cache on desktop. Guarded by a UserDefaults flag so it runs once.
    func migrateToRuntimeProviderManagementIfNeeded(store: any ProviderStore) async {
        let migrationKey = "talkify.provider-connections.migrated-to-http.v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        // Only migrate connections that actually exist locally.
        let existing = registry.connections
        guard !existing.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            // Sync the cache to whatever the runtime already has.
            await refreshCacheFromRuntime(store: store)
            return
        }

        var migratedCount = 0
        for connection in existing {
            do {
                _ = try await store.upsertProvider(connection.asRuntimeProviderDefinition())
                migratedCount += 1
            } catch {
                providerStoreLogger.error("Provider 迁移失败：\(connection.id, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            }
        }
        UserDefaults.standard.set(true, forKey: migrationKey)

        // After migration, registry is a read-only cache of the runtime source.
        await refreshCacheFromRuntime(store: store)
        providerStoreLogger.info("Provider 迁移完成：\(migratedCount)/\(existing.count, privacy: .public) 个连接已写入 runtime /v1/providers")
    }

    /// Whether the desktop runtime (codeagentd daemon) is reachable for
    /// /v1/providers management. When offline, the settings page shows a
    /// degraded state and writes fall back to the local registry + injection.
    var isDaemonOffline: Bool {
        // On desktop, a providerStore is only installed once the daemon started;
        // a nil store on macOS means no daemon / not yet ready.
        #if os(macOS)
        return providerStore == nil
        #else
        return false
        #endif
    }

    /// A2 secrets push: read the Keychain llm credentials from the composite
    /// credential store and POST them to the daemon's /v1/secrets, so
    /// GET /v1/runtime/models can rebuild the catalog with available=true.
    ///
    /// - `only`: when set, pushes just that target (credential change path).
    ///   When nil, pushes ALL llm entries (daemon start path). Idempotent.
    func pushLLMCredentialsToDaemon(only target: CredentialTarget? = nil) async {
        guard let secretsClient = secretsClient else { return }
        let entries = await sharedLLMSecretsEntries(only: target)
        guard !entries.isEmpty else { return }
        do {
            try await secretsClient.push(entries)
            lastSecretsPushError = nil
            onSecretsPushed?()
        } catch {
            lastSecretsPushError = error.localizedDescription
            providerStoreLogger.error(
                "推送 llm secrets 到 daemon 失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Shared llm/* → secrets-envelope mapping, used by both the A2 daemon push
    /// (POST /v1/secrets) and the shared ~/.codeagent/secrets.json file write.
    private func sharedLLMSecretsEntries(only target: CredentialTarget? = nil) async -> [String: RuntimeSecretsBodyEntry] {
        let map = (try? await credentialStore.all()) ?? CredentialMap()
        return SharedSecretsFile.llmEntries(from: map, only: target).mapValues {
            RuntimeSecretsBodyEntry(type: $0.type, secret: $0.secret)
        }
    }

    /// Shared-file write: mirror the A2 push timing — daemon-start full write
    /// (only == nil) and credential change per-target (only == target).
    func writeSharedSecretsFile(only target: CredentialTarget? = nil) async {
        let map = (try? await credentialStore.all()) ?? CredentialMap()
        let entries = SharedSecretsFile.llmEntries(from: map, only: target)
        guard !entries.isEmpty else { return }
        do {
            try SharedSecretsFile.write(entries: entries)
        } catch {
            sharedSecretsFileError = error.localizedDescription
            providerStoreLogger.error(
                "写入 ~/.codeagent/secrets.json 失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func upsertGateway(
        baseURL: URL,
        models: [ProviderModel],
        allowsInsecurePrivateNetworkHTTP: Bool = false
    ) throws {
        let connection = ProviderConnection(
            id: ProviderConnection.talkifyGatewayID,
            providerID: ProviderConnection.talkifyGatewayID,
            displayName: "Talkify Gateway",
            transport: .openAIChatCompletions,
            authentication: .gatewayAccount,
            baseURL: baseURL,
            modelSource: .gatewayRemote,
            models: models,
            isEnabled: true,
            allowsInsecurePrivateNetworkHTTP: allowsInsecurePrivateNetworkHTTP
        )
        try registry.upsert(connection)
        didMutateRegistry()
    }

    func removeGatewayConnection() {
        _ = registry.remove(connectionID: ProviderConnection.talkifyGatewayID)
        didMutateRegistry()
    }

    func setDefaultModel(_ id: String?) {
        catalog.setDefaultModel(id: id)
        onStructuralChange?()
    }

    func reloadCatalog() {
        catalog.reload(from: registry)
    }

    func catalogSnapshot() -> ProviderCatalogSnapshot {
        ProviderCatalogSnapshot(
            models: catalog.models,
            defaultModelID: catalog.defaultModelID
        )
    }

    // MARK: - connection-flattening (Wave 3)

    /// connection-flattening v2: 把当前所有连接序列化为 connectionsJSON
    /// （non-secret connection DEFINITIONS）。经 AgentKit 的
    /// `RuntimeProviderConfigurationBuilder.buildConnectionsJSON` 构建，
    /// 不手拼 wire。ProviderConnection.id 与 connectionsJSON 的 connection id
    /// 1:1 对应（已是唯一小写 slug）。
    func buildConnectionsJSON() throws -> String {
        try RuntimeProviderConfigurationBuilder.buildConnectionsJSON(
            connections: registry.connections
        )
    }

    /// Test seam: serialize an explicit connection list through the same
    /// AgentKit builder the runtime channel uses, without touching the registry.
    static func buildConnectionsJSONForTesting(
        connections: [ProviderConnection]
    ) throws -> String {
        try RuntimeProviderConfigurationBuilder.buildConnectionsJSON(
            connections: connections
        )
    }

    /// secretsJSON（connection-flattening bridging）：同时输出 v1 namespaced
    /// （`{namespace}/{name}`）与 v2 flat（connection id）两种 key，使新旧
    /// runtime 都能解析。value 形状两种模式下字节一致。Gateway 命名空间路由
    /// （gateway → AppCredentialStore，llm → KeychainCredentialStore）保持
    /// 不变，由 CompositeCredentialStore 负责。
    func secretsJSONForInjection() async -> String {
        let map = (try? await credentialStore.all()) ?? CredentialMap()
        return map.toSecretsJSON(keyMode: .dual)
    }

    func markRuntimeConfigurationPending() {
        isApplyingRuntimeConfiguration = true
        runtimeConfigurationError = nil
        runtimeConfigurationWaitDescription = nil
        // Runtime restart creates a short interval where neither the old nor
        // the new alias set is safe to submit. An explicit empty catalog keeps
        // Composer editable while disabling model selection and sending.
        modelSettings.applyUnifiedCatalog([], defaultModelID: nil)
    }

    func markRuntimeConfigurationFailed(_ error: Error) {
        isApplyingRuntimeConfiguration = true
        runtimeConfigurationError = error.localizedDescription
        runtimeConfigurationWaitDescription = nil
    }

    func markRuntimeConfigurationWaiting(_ description: String?) {
        isApplyingRuntimeConfiguration = true
        runtimeConfigurationError = nil
        runtimeConfigurationWaitDescription = description
    }

    /// Publishes only the catalog that the embedded Runtime has successfully
    /// configured. Registry edits stay invisible to Composer until this point,
    /// preventing it from sending an alias that the running Runtime does not know.
    func publishAppliedCatalog(
        _ snapshot: ProviderCatalogSnapshot,
        hasPendingConfiguration: Bool
    ) {
        isApplyingRuntimeConfiguration = hasPendingConfiguration
        guard !hasPendingConfiguration else {
            modelSettings.applyUnifiedCatalog([], defaultModelID: nil)
            return
        }
        modelSettings.applyUnifiedCatalog(
            snapshot.models,
            defaultModelID: snapshot.defaultModelID
        )
        runtimeConfigurationError = nil
        runtimeConfigurationWaitDescription = nil
    }

    private func didMutateRegistry() {
        reloadCatalog()
        onStructuralChange?()
    }
}

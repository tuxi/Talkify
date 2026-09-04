import Foundation
import AgentKit
import OSLog

private let providerStoreLogger = Logger(subsystem: "com.objc.chat", category: "ProviderStore")

/// Classifies active Runtime work for the server-switch guard. It no longer
/// gates the (removed) provider apply loop, but the Runtime Server settings page
/// still uses it to warn before switching away from a busy server.
enum ProviderRuntimeActivityPolicy {
    static func blockingDescriptions(
        in snapshot: RuntimeActivitySnapshot
    ) -> [String] {
        snapshot.sessions.compactMap { activity in
            var reasons: [String] = []
            let state = activity.state.lowercased()
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
    /// Invoked when a provider definition was persisted but needs a runtime
    /// restart to take effect (`applied == false`). AppContainer injects the
    /// embedded restart on iOS; the desktop daemon surfaces a restart hint.
    var onRuntimeRestartNeeded: (() async -> Void)?
    private(set) var isApplyingRuntimeConfiguration = false
    private(set) var runtimeConfigurationError: String?

    /// Provider store (AgentKit `any ProviderStore`). Non-nil whenever the active
    /// runtime (daemon or embedded) exposes its HTTP management surface. Provider
    /// definitions are managed via /v1/providers and the local registry is a
    /// read-only cache on every platform.
    var providerStore: (any ProviderStore)?

    /// Called after a successful secrets push — AppContainer uses it to
    /// re-GET /v1/runtime/models so the model list reflects available=true.
    var onSecretsPushed: (() -> Void)?

    /// Called after provider definitions are applied. The host refreshes the
    /// server-scoped runtime model catalog because provider definitions and the
    /// published/available model catalog are separate endpoints.
    var onRuntimeConfigurationApplied: (() async -> Void)?

    /// Last secrets-push error, surfaced in the settings page (kept usable).
    private(set) var lastSecretsPushError: String?

    /// Last shared-secrets-file write error (~/.codeagent/secrets.json).
    private(set) var sharedSecretsFileError: String?

    /// Connection IDs whose PUT/DELETE returned `applied: false`
    /// ("persisted, restart required"). Shown in the settings page.
    private(set) var pendingRestartConnectionIDs: Set<String> = []

    /// Provider templates fetched from the runtime (GET /v1/provider-templates).
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

    var connections: [ProviderConnection] {
        registry.connections
    }
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
            // Definition over HTTP; credential value stays in Keychain.
            let result = try await store.upsertProvider(connection.asRuntimeProviderDefinition())
            if result.applied {
                pendingRestartConnectionIDs.remove(connection.id)
                await refreshCacheFromRuntime(store: store)
                await onRuntimeConfigurationApplied?()
            } else {
                pendingRestartConnectionIDs.insert(connection.id)
                await restartRuntimeIfNeeded(store: store)
            }
        } else {
            // Daemon offline fallback: keep the local registry write path.
            try registry.upsert(connection)
            reloadCatalog()
        }
    }

    func remove(connectionID: String) async throws {
        guard let connection = registry.connection(id: connectionID) else {
            // Cache may already be refreshed; allow delete anyway.
            if let store = providerStore {
                let result = try await store.deleteProvider(id: connectionID)
                if result.applied {
                    pendingRestartConnectionIDs.remove(connectionID)
                    await refreshCacheFromRuntime(store: store)
                    await onRuntimeConfigurationApplied?()
                } else {
                    pendingRestartConnectionIDs.insert(connectionID)
                    await restartRuntimeIfNeeded(store: store)
                }
            }
            return
        }

        if let store = providerStore {
            let result = try await store.deleteProvider(id: connectionID)
            if result.applied {
                pendingRestartConnectionIDs.remove(connectionID)
                await refreshCacheFromRuntime(store: store)
                await onRuntimeConfigurationApplied?()
            } else {
                pendingRestartConnectionIDs.insert(connectionID)
                await restartRuntimeIfNeeded(store: store)
            }
        } else {
            _ = registry.remove(connectionID: connectionID)
            reloadCatalog()
        }
        if connection.authentication == .apiKey {
            try await credentialStore.set(Credential(kind: .bearer, secret: ""), for: .llm(connection.id))
            await pushLLMCredentialsToDaemon(only: .llm(connection.id))
            await writeSharedSecretsFile(only: .llm(connection.id))
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
                        await onRuntimeConfigurationApplied?()
                    } else {
                        pendingRestartConnectionIDs.insert(connectionID)
                        await restartRuntimeIfNeeded(store: store)
                    }
                } catch {
                    runtimeConfigurationError = error.localizedDescription
                }
            }
        } else {
            registry.setEnabled(enabled, connectionID: connectionID)
            reloadCatalog()
        }
    }

    /// Shared `applied == false` path: the definition is persisted but the live
    /// runtime is unchanged. On iOS AppContainer injects an embedded restart;
    /// the desktop daemon only marks the connection for a restart hint.
    private func restartRuntimeIfNeeded(store: any ProviderStore) async {
        isApplyingRuntimeConfiguration = true
        defer { isApplyingRuntimeConfiguration = false }
        await onRuntimeRestartNeeded?()
        await refreshCacheFromRuntime(store: store)
    }

    /// Fetch provider templates from the runtime.
    func loadProviderTemplates(store: (any ProviderStore)? = nil) async {
        guard let store = store ?? providerStore else { return }
        do {
            providerTemplates = try await store.listProviderTemplates()
        } catch {
            providerStoreLogger.error("加载 provider 模板失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rebuild the local registry cache from listProviders().
    /// Also re-GETs /v1/runtime/models to refresh the model list.
    func refreshCacheFromRuntime(store: (any ProviderStore)? = nil) async {
        guard let store = store ?? providerStore else { return }
        do {
            let providers = try await store.listProviders()
            let connections = providers.map { $0.asProviderConnection() }
            try registry.replaceAll(connections)
            reloadCatalog()
            await loadProviderTemplates(store: store)
        } catch {
            runtimeConfigurationError = error.localizedDescription
        }
    }

    /// Applies a settings.json snapshot immediately. The embedded and daemon
    /// runtimes also watch the file, but this explicit call gives the settings
    /// UI an acknowledgement path when it writes a complete document directly.
    func reloadRuntimeSettings(store: (any ProviderStore)? = nil) async {
        guard let store = store ?? providerStore else { return }
        do {
            try await store.reloadSettings()
            runtimeConfigurationError = nil
            await refreshCacheFromRuntime(store: store)
            onSecretsPushed?()
        } catch {
            runtimeConfigurationError = error.localizedDescription
            providerStoreLogger.error(
                "重新加载 Runtime settings 失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// One-time migration: existing UserDefaults connections → PUT to runtime,
    /// then registry becomes a read-only cache. Guarded by a UserDefaults flag.
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
    /// degraded state and writes fall back to the local registry.
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
    /// credential store and POST them to the runtime's /v1/secrets, so
    /// GET /v1/runtime/models can rebuild the catalog with available=true.
    ///
    /// - `only`: when set, pushes just that target (credential change path).
    ///   When nil, pushes ALL llm entries (start path). Idempotent.
    func pushLLMCredentialsToDaemon(only target: CredentialTarget? = nil) async {
        guard let store = providerStore else { return }
        let entries = await sharedLLMSecretsEntries(only: target)
        guard !entries.isEmpty else { return }
        do {
            try await withRetry(maxAttempts: 3, baseDelay: 1_000_000_000) {
                try await store.pushSecrets(entries)
            }

            lastSecretsPushError = nil
            onSecretsPushed?()
        } catch {
            lastSecretsPushError = error.localizedDescription
            providerStoreLogger.error(
                "推送 llm secrets 到 runtime 失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Shared llm/* → secrets-envelope mapping, used by both the A2 secrets push
    /// (POST /v1/secrets) and the shared ~/.codeagent/secrets.json file write.
    private func sharedLLMSecretsEntries(only target: CredentialTarget? = nil) async -> [String: RuntimeSecretEntry] {
        let map = (try? await credentialStore.all()) ?? CredentialMap()
        return SharedSecretsFile.llmEntries(from: map, only: target)
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
    ) async throws {
        let connection = ProviderConnection(
            id: ProviderConnection.talkifyGatewayID,
            displayName: "Talkify Gateway",
            transport: .openAIChatCompletions,
            authentication: .gatewayAccount,
            baseURL: baseURL,
            modelSource: .gatewayRemote,
            models: models,
            isEnabled: true,
            allowsInsecurePrivateNetworkHTTP: allowsInsecurePrivateNetworkHTTP
        )
        if let store = providerStore {
            let result = try await store.upsertProvider(connection.asRuntimeProviderDefinition())
            if result.applied {
                pendingRestartConnectionIDs.remove(connection.id)
                await refreshCacheFromRuntime(store: store)
                await onRuntimeConfigurationApplied?()
            } else {
                pendingRestartConnectionIDs.insert(connection.id)
                await restartRuntimeIfNeeded(store: store)
            }
        } else {
            try registry.upsert(connection)
            reloadCatalog()
        }
        // Gateway token lives in the gateway credential store; push it over
        // /v1/secrets so the gateway provider resolves without a restart.
        await pushGatewayCredentialToRuntime()
    }

    func removeGatewayConnection() async {
        if let store = providerStore {
            if let result = try? await store.deleteProvider(id: ProviderConnection.talkifyGatewayID),
               !result.applied {
                pendingRestartConnectionIDs.insert(ProviderConnection.talkifyGatewayID)
                await restartRuntimeIfNeeded(store: store)
            } else {
                await refreshCacheFromRuntime(store: store)
            }
        } else {
            _ = registry.remove(connectionID: ProviderConnection.talkifyGatewayID)
            reloadCatalog()
        }
    }

    func setDefaultModel(_ id: String?) {
        catalog.setDefaultModel(id: id)
    }

    /// Push the Gateway account token (gateway/default) into the runtime's
    /// mutable resolver. Called on login/refresh so the gateway provider stays
    /// resolvable without restarting.
    func pushGatewayCredentialToRuntime() async {
        guard let store = providerStore else {
            providerStoreLogger.info("跳过 gateway/default 凭据推送：runtime provider store 尚未就绪")
            return
        }
        guard let cred = try? await credentialStore.resolve(.gateway),
              cred.kind == .bearer,
              !cred.secret.isEmpty else { return }
        do {
            try await store.pushSecrets([
                "gateway/default": RuntimeSecretEntry(type: "bearer", secret: cred.secret)
            ])
            lastSecretsPushError = nil
            providerStoreLogger.info("已推送 gateway/default 凭据：type=bearer secret_length=\(cred.secret.count, privacy: .public)")
            onSecretsPushed?()
        } catch {
            lastSecretsPushError = error.localizedDescription
            providerStoreLogger.error(
                "推送 gateway 凭据到 runtime 失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func reloadCatalog() {
        catalog.reload(from: registry)
    }
}


/// 带指数退避的异步重试工具
/// - Parameters:
///   - maxAttempts: 总尝试次数（含首次）
///   - baseDelay: 首次失败后的基础等待时间（纳秒），之后每次翻倍
func withRetry<T>(
    maxAttempts: Int = 3,
    baseDelay: UInt64 = 1_000_000_000,
    operation: () async throws -> T
) async rethrows -> T {
    for attempt in 0..<maxAttempts {
        do {
            return try await operation()
        } catch {
            guard attempt < maxAttempts - 1 else { throw error }
            let delay = baseDelay * (1 << attempt)
            try? await Task.sleep(nanoseconds: delay)
        }
    }
    // 理论上不会走到这里，满足编译器
    fatalError("Unreachable")
}

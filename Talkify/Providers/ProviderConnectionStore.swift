import Foundation
import AgentKit

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
            } else if isNew && directCredentialStore.resolveSync(.llm(connection.id)) == nil {
                throw ProviderConnectionStoreError.apiKeyRequired
            }
        }
        try registry.upsert(connection)
        didMutateRegistry()
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

    func remove(connectionID: String) async throws {
        guard let connection = registry.connection(id: connectionID) else { return }
        if connection.authentication == .apiKey {
            try await credentialStore.remove(.llm(connection.id))
        }
        _ = registry.remove(connectionID: connectionID)
        didMutateRegistry()
    }

    func removeGatewayConnection() {
        _ = registry.remove(connectionID: ProviderConnection.talkifyGatewayID)
        didMutateRegistry()
    }

    func setEnabled(_ enabled: Bool, connectionID: String) {
        registry.setEnabled(enabled, connectionID: connectionID)
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

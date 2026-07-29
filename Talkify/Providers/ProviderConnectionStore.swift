import Foundation
import AgentKit

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
        modelSettings.applyUnifiedCatalog(catalog)
        onStructuralChange?()
    }

    func reloadCatalog() {
        catalog.reload(from: registry)
        modelSettings.applyUnifiedCatalog(catalog)
    }

    private func didMutateRegistry() {
        reloadCatalog()
        onStructuralChange?()
    }
}

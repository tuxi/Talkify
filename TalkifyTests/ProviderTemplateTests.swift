import XCTest
import AgentKit
@testable import Talkify

final class ProviderTemplateTests: XCTestCase {
    func testIntegrationSettingsKeepServersBeforeProvidersAndModels() {
        XCTAssertEqual(
            SettingsSection.allCases.filter { $0.group == .integrations },
            [.servers, .providers, .models]
        )
    }

    func testBuiltInTemplatesHaveUniqueIDsAndSupportedTransports() {
        let templates = TalkifyProviderTemplate.builtIn
        XCTAssertEqual(Set(templates.map(\.id)).count, templates.count)
        XCTAssertNotNil(templates.first { $0.id == ProviderConnection.talkifyGatewayID })
        XCTAssertNotNil(templates.first { $0.id == "openai-compatible" })
        XCTAssertNotNil(templates.first { $0.id == "ollama" })
    }

    func testDeepSeekTemplateUsesCurrentV4ModelIDs() throws {
        let template = try XCTUnwrap(
            TalkifyProviderTemplate.builtIn.first { $0.id == "deepseek" }
        )
        XCTAssertEqual(template.baseURL?.absoluteString, "https://api.deepseek.com")
        XCTAssertEqual(
            Set(template.models.map(\.id)),
            ["deepseek-v4-flash", "deepseek-v4-pro"]
        )
    }

    func testSuggestedConnectionIDDoesNotCollide() throws {
        let template = try XCTUnwrap(
            TalkifyProviderTemplate.builtIn.first { $0.id == "qwen" }
        )
        XCTAssertEqual(
            template.suggestedConnectionID(existing: ["qwen", "qwen-2"]),
            "qwen-3"
        )
    }

    func testIdleRuntimeQueuePositionZeroDoesNotBlockConfigurationApply() {
        let snapshot = RuntimeActivitySnapshot(
            sessions: [
                RuntimeSessionActivity(
                    sessionID: "idle-session",
                    state: "idle",
                    pendingApprovalCount: 0,
                    pendingClientToolCount: 0,
                    queuePosition: 0
                )
            ]
        )

        XCTAssertFalse(ProviderRuntimeActivityPolicy.hasActiveRuntimeWork(snapshot))
    }

    func testPositiveQueuePositionAndActiveTurnBlockConfigurationApply() {
        let snapshot = RuntimeActivitySnapshot(
            sessions: [
                RuntimeSessionActivity(
                    sessionID: "queued-session",
                    state: "queued",
                    queuePosition: 1
                ),
                RuntimeSessionActivity(
                    sessionID: "running-session",
                    activeTurnID: "turn-1",
                    state: "running",
                    queuePosition: 0
                )
            ]
        )

        XCTAssertEqual(
            ProviderRuntimeActivityPolicy.blockingDescriptions(in: snapshot).count,
            2
        )
    }

    func testPausedSessionAwaitingUserInputDoesNotBlockConfigurationApply() {
        let snapshot = RuntimeActivitySnapshot(
            sessions: [
                RuntimeSessionActivity(
                    sessionID: "paused-session",
                    activeTurnID: "turn-1",
                    state: "paused",
                    queuePosition: 0
                )
            ]
        )

        XCTAssertFalse(ProviderRuntimeActivityPolicy.hasActiveRuntimeWork(snapshot))
    }

    @MainActor
    func testSavedProviderIsNotPublishedBeforeRuntimeConfigurationApplies() async throws {
        let suiteName = "ProviderTemplateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let modelSettings = ModelSettingsStore(defaults: defaults)
        let store = ProviderConnectionStore(
            modelSettings: modelSettings,
            gatewayCredentialStore: MemoryCredentialStore(),
            defaults: defaults
        )
        var structuralChangeCount = 0
        store.onStructuralChange = {
            structuralChangeCount += 1
        }

        let connection = ProviderConnection(
            id: "deepseek",
            providerID: "deepseek",
            displayName: "DeepSeek",
            transport: .openAIChatCompletions,
            authentication: .none,
            baseURL: try XCTUnwrap(URL(string: "https://api.deepseek.com")),
            models: [ProviderModel(id: "deepseek-v4-flash")]
        )

        try await store.save(connection, apiKey: nil, isNew: true)

        XCTAssertEqual(structuralChangeCount, 1)
        XCTAssertEqual(store.catalog.models.count, 1)
        XCTAssertEqual(modelSettings.unifiedModels, [])

        let applied = store.catalogSnapshot()
        store.markRuntimeConfigurationPending()
        store.publishAppliedCatalog(applied, hasPendingConfiguration: false)

        XCTAssertEqual(modelSettings.unifiedModels?.map(\.id), applied.models.map(\.id))
        XCTAssertFalse(store.isApplyingRuntimeConfiguration)

        store.markRuntimeConfigurationPending()
        XCTAssertEqual(modelSettings.unifiedModels, [])
        XCTAssertTrue(store.isApplyingRuntimeConfiguration)

        store.publishAppliedCatalog(applied, hasPendingConfiguration: false)
        XCTAssertEqual(modelSettings.unifiedModels?.map(\.id), applied.models.map(\.id))
    }
}

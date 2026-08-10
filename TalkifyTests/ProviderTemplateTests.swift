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
        let templates = TalkifyProviderTemplate.all(from: sampleTemplates)
        XCTAssertEqual(Set(templates.map(\.id)).count, templates.count)
        XCTAssertNotNil(templates.first { $0.id == ProviderConnection.talkifyGatewayID })
        XCTAssertNotNil(templates.first { $0.id == "openai-compatible" })
        XCTAssertNotNil(templates.first { $0.id == "ollama" })
    }

    func testDeepSeekTemplateUsesCurrentV4ModelIDs() throws {
        let template = try XCTUnwrap(
            TalkifyProviderTemplate.all(from: sampleTemplates).first { $0.id == "deepseek" }
        )
        XCTAssertEqual(template.baseURL?.absoluteString, "https://api.deepseek.com")
        XCTAssertEqual(
            Set(template.models.map(\.id)),
            ["deepseek-v4-flash", "deepseek-v4-pro"]
        )
    }

    func testSuggestedConnectionIDDoesNotCollide() throws {
        let template = try XCTUnwrap(
            TalkifyProviderTemplate.all(from: sampleTemplates).first { $0.id == "qwen" }
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

// MARK: - Test helpers

private let sampleTemplates: [RuntimeProviderTemplate] = [
    RuntimeProviderTemplate(
        id: "deepseek",
        displayName: "DeepSeek",
        summary: "使用 DeepSeek API 密钥连接",
        kind: "api_key",
        baseURL: "https://api.deepseek.com",
        api: "openai",
        env: "DEEPSEEK_API_KEY",
        models: [
            RuntimeProviderTemplateModel(id: "deepseek-v4-flash", runtimeAlias: "deepseek", contextWindow: 1_000_000, supportsTools: true, supportsReasoning: true, inputModalities: ["text"], webSearch: true, inputPricePerMillion: 0.16, outputPricePerMillion: 0.32),
            RuntimeProviderTemplateModel(id: "deepseek-v4-pro", runtimeAlias: "deepseek-pro", contextWindow: 1_000_000, supportsTools: true, supportsReasoning: true, inputModalities: ["text"], inputPricePerMillion: 0.45, outputPricePerMillion: 0.90),
        ]
    ),
    RuntimeProviderTemplate(
        id: "qwen",
        displayName: "Alibaba Qwen",
        summary: "使用阿里云百炼 OpenAI 兼容接口",
        kind: "api_key",
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        api: "openai",
        env: "DASHSCOPE_API_KEY",
        models: [
            RuntimeProviderTemplateModel(id: "qwen3-coder-plus", contextWindow: 128_000, supportsTools: true, inputModalities: ["text"]),
        ]
    ),
    RuntimeProviderTemplate(
        id: "glm",
        displayName: "Zhipu GLM",
        summary: "使用智谱 OpenAI 兼容接口",
        kind: "api_key",
        baseURL: "https://open.bigmodel.cn/api/paas/v4",
        api: "openai",
        env: "GLM_API_KEY",
        models: [
            RuntimeProviderTemplateModel(id: "glm-4.7", contextWindow: 128_000, supportsTools: true, supportsReasoning: true, inputModalities: ["text"]),
        ]
    ),
    RuntimeProviderTemplate(
        id: "openrouter",
        displayName: "OpenRouter",
        summary: "通过一个 API 密钥使用多个模型",
        kind: "api_key",
        baseURL: "https://openrouter.ai/api/v1",
        api: "openai",
        env: "OPENROUTER_API_KEY",
        models: [
            RuntimeProviderTemplateModel(id: "openrouter/auto", runtimeAlias: "openrouter", contextWindow: 200_000, supportsTools: true, inputModalities: ["text"]),
        ]
    ),
    RuntimeProviderTemplate(
        id: "ollama",
        displayName: "Ollama",
        summary: "连接本机或局域网中的 Ollama",
        kind: "local",
        baseURL: "http://localhost:11434/v1",
        api: "ollama",
        env: nil,
        models: nil
    ),
    RuntimeProviderTemplate(
        id: ProviderConnection.talkifyGatewayID,
        displayName: "Talkify Gateway",
        summary: "使用 Talkify 账户、订阅模型和云端能力",
        kind: "gateway",
        baseURL: nil,
        api: "openai",
        env: nil,
        models: nil
    ),
]

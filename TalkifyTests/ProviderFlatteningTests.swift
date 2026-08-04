import XCTest
import AgentKit
@testable import Talkify

/// Wave 3 connection-flattening host tests:
/// C1 connectionsJSON construction, C2 dual-key secretsJSON, C3 catalog v2 handling.
final class ProviderFlatteningTests: XCTestCase {

    // MARK: - C1: connectionsJSON construction from ProviderConnection

    @MainActor
    func testConnectionsJSONBuildsOpenAIConnectionFromProviderConnection() throws {
        let connection = ProviderConnection(
            id: "deepseek",
            providerID: "deepseek",
            displayName: "DeepSeek",
            transport: .openAIChatCompletions,
            authentication: .apiKey,
            baseURL: try XCTUnwrap(URL(string: "https://api.deepseek.com")),
            models: [ProviderModel(id: "deepseek-v4-flash", displayName: "DeepSeek V4 Flash")]
        )
        let json = try ProviderConnectionStore.buildConnectionsJSONForTesting(connections: [connection])
        let document = try JSONDecoder().decode(
            RuntimeConnectionsDocument.self,
            from: Data(json.utf8)
        )
        let definition = try XCTUnwrap(document.connections["deepseek"])
        XCTAssertEqual(definition.id, "deepseek")
        XCTAssertEqual(definition.api, "openai")
        XCTAssertEqual(definition.baseURL, "https://api.deepseek.com")
        XCTAssertEqual(definition.credential?.source, "injected")
        XCTAssertEqual(definition.credential?.ref, "deepseek")
        XCTAssertEqual(definition.models.count, 1)
        XCTAssertEqual(definition.models[0].wireModelID, "deepseek-v4-flash")
        // runtime alias matches the Composer alias (connection+model two-level).
        XCTAssertEqual(
            definition.models[0].runtimeAlias,
            UnifiedModelDescriptor.makeRuntimeAlias(
                connectionID: "deepseek",
                wireModelID: "deepseek-v4-flash"
            )
        )
    }

    @MainActor
    func testConnectionsJSONGatewayGoesThroughSameChannel() throws {
        let connection = ProviderConnection(
            id: ProviderConnection.talkifyGatewayID,
            providerID: ProviderConnection.talkifyGatewayID,
            displayName: "Talkify Gateway",
            transport: .openAIChatCompletions,
            authentication: .gatewayAccount,
            baseURL: try XCTUnwrap(URL(string: "https://gw.example.com/agent")),
            modelSource: .gatewayRemote,
            models: [ProviderModel(id: "gw-model", displayName: "Gateway Model")]
        )
        let json = try ProviderConnectionStore.buildConnectionsJSONForTesting(connections: [connection])
        let document = try JSONDecoder().decode(
            RuntimeConnectionsDocument.self,
            from: Data(json.utf8)
        )
        let definition = try XCTUnwrap(
            document.connections[ProviderConnection.talkifyGatewayID]
        )
        XCTAssertEqual(definition.api, "gateway")
        XCTAssertEqual(definition.credential?.source, "injected")
        XCTAssertEqual(definition.credential?.ref, "gateway")
    }

    @MainActor
    func testDisabledConnectionIsExcludedFromConnectionsJSON() throws {
        let connection = ProviderConnection(
            id: "qwen",
            providerID: "qwen",
            displayName: "Qwen",
            transport: .openAIChatCompletions,
            authentication: .apiKey,
            baseURL: try XCTUnwrap(URL(string: "https://dashscope.aliyuncs.com")),
            models: [ProviderModel(id: "qwen-plus")],
            isEnabled: false
        )
        let json = try ProviderConnectionStore.buildConnectionsJSONForTesting(connections: [connection])
        let document = try JSONDecoder().decode(
            RuntimeConnectionsDocument.self,
            from: Data(json.utf8)
        )
        XCTAssertTrue(document.connections.isEmpty)
    }

    // MARK: - C2: dual-key secretsJSON bridging

    func testSecretsJSONDualModeEmitsNamespacedAndFlatKeys() async throws {
        let store = MemoryCredentialStore()
        try await store.set(
            Credential(kind: .bearer, secret: "sk-test"),
            for: .llm("deepseek")
        )
        try await store.set(
            Credential(kind: .bearer, secret: "gw-token"),
            for: .gateway
        )
        let map = try await store.all()

        let dual = map.toSecretsJSON(keyMode: .dual)
        // v1 namespaced keys retained for old runtimes.
        XCTAssertTrue(dual.contains("\"llm/deepseek\""))
        XCTAssertTrue(dual.contains("\"gateway/default\""))
        // v2 flat keys present for new runtimes.
        XCTAssertTrue(dual.contains("\"deepseek\""))
        XCTAssertTrue(dual.contains("\"gateway\""))
        // Values carry the secret regardless of key form.
        XCTAssertTrue(dual.contains("sk-test"))
    }

    // MARK: - C3: catalog v2 handling

    func testCatalogV2SchemaDecodesAndFiltersUnavailableModels() throws {
        let v2JSON = """
        {
          "schema": "runtime-model-catalog/v2",
          "revision": 7,
          "default_runtime_alias": "provider.ZGVlcHNlZWs=.model.ZGVlcHNlZWstdjQtcHJv",
          "connections": [
            {
              "id": "deepseek",
              "provider_id": "deepseek",
              "display_name": "DeepSeek",
              "billing_source": "provider",
              "credential": { "status": "configured", "source": "injected" },
              "models": [
                {
                  "runtime_alias": "provider.ZGVlcHNlZWs=.model.ZGVlcHNlZWstdjQtcHJv",
                  "wire_model_id": "deepseek-v4-pro",
                  "display_name": "DeepSeek V4 Pro",
                  "context_window": 1000000,
                  "supports_tools": true,
                  "supports_reasoning": true,
                  "input_modalities": ["text"],
                  "available": true
                },
                {
                  "runtime_alias": "provider.ZGVlcHNlZWs=.model.ZGVlcHNlZWstdjQtcHJv",
                  "wire_model_id": "deepseek-v4-flash",
                  "display_name": "DeepSeek V4 Flash",
                  "context_window": 1000000,
                  "supports_tools": true,
                  "supports_reasoning": false,
                  "input_modalities": ["text"],
                  "available": false,
                  "unavailable_reason": "quota exhausted"
                }
              ]
            }
          ]
        }
        """
        let catalog = try JSONDecoder().decode(
            RuntimeServerModelCatalog.self,
            from: Data(v2JSON.utf8)
        )
        XCTAssertTrue(catalog.hasSupportedSchema)
        XCTAssertEqual(catalog.revision, 7)

        let models = catalog.unifiedModels(serverConnectionID: nil)
        // unavailable model is filtered out; unavailable_reason is not surfaced as a model.
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.connectionID, "deepseek")
        XCTAssertEqual(models.first?.wireModelID, "deepseek-v4-pro")
        XCTAssertEqual(models.first?.billingSource, "provider")

        // Per-connection credential subobject decodes (v2 addition).
        let connection = try XCTUnwrap(catalog.connections.first)
        XCTAssertEqual(connection.credential?.status, "configured")
        XCTAssertEqual(connection.credential?.source, "injected")
    }

    func testCatalogSchemaPrefixMatchAcceptsV1AndRejectsForeign() throws {
        let v1 = try JSONDecoder().decode(
            RuntimeServerModelCatalog.self,
            from: Data("""
            {"schema":"runtime-model-catalog/v1","revision":1,"default_runtime_alias":"","connections":[]}
            """.utf8)
        )
        XCTAssertTrue(v1.hasSupportedSchema)

        let foreign = try JSONDecoder().decode(
            RuntimeServerModelCatalog.self,
            from: Data("""
            {"schema":"other-schema/v9","revision":1,"default_runtime_alias":"","connections":[]}
            """.utf8)
        )
        XCTAssertFalse(foreign.hasSupportedSchema)
    }
}

import XCTest
import AgentKit
@testable import Talkify

/// Provider/catalog tests. The connection-flattening injection channel
/// (buildConnectionsJSON / dual-key secretsJSON) was removed when provider
/// management moved to the runtime's /v1/providers + /v1/secrets HTTP surface;
/// the catalog-v2 decoding tests remain valid.
final class ProviderFlatteningTests: XCTestCase {

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

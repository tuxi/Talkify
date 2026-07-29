import XCTest
import AgentKit
@testable import Talkify

final class ProviderTemplateTests: XCTestCase {
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
}

import AgentKit
import ClientToolsKit
import XCTest

final class InspectUIImageRegistrationTests: XCTestCase {
    func testRegistryFindsInspectUIImageTool() async {
        let registry = ToolRegistry()
        await registry.register(InspectUIImageTool())

        let found = await registry.find(name: "inspect_ui_image")
        XCTAssertEqual(found?.name, "inspect_ui_image")

        let names = await registry.registeredNames
        XCTAssertTrue(names.contains("inspect_ui_image"))
    }

    func testToolInfoRoundTripsDescriptionAndSchema() throws {
        let tool = InspectUIImageTool()
        let info = ClientToolInfo(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ClientToolInfo.self, from: data)

        XCTAssertEqual(decoded.name, "inspect_ui_image")
        XCTAssertEqual(decoded.description, tool.description)
        XCTAssertTrue(decoded.description.contains("ui_evidence.v1"))
        XCTAssertNotNil(decoded.inputSchema)
    }
}

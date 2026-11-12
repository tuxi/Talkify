import AgentKit
import ClientToolsKit
import CoreKit
import XCTest
@testable import Talkify

final class InspectUIImageRegistrationTests: XCTestCase {
    func testRegistryFindsInspectUIImageTool() async {
        let registry = ToolRegistry()
        await registry.register(InspectUIImageTool())

        let found = await registry.find(name: "inspect_ui_image")
        XCTAssertEqual(found?.name, "inspect_ui_image")

        let names = await registry.registeredNames
        XCTAssertTrue(names.contains("inspect_ui_image"))
    }

    @MainActor
    func testAppContainerRegistersInspectUIImageTool() async throws {
        let authManager = AuthManager(refreshTokenHandler: { token in token })
        let container = AppContainer(
            authManager: authManager,
            environmentManager: EnvironmentManager(),
            deviceManager: DeviceManager()
        )

        var names: [String] = []
        for _ in 0..<100 {
            names = await container.toolRegistry.registeredNames
            if names.contains("inspect_ui_image") { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(names.contains("inspect_ui_image"), "registered tools: \(names)")
        XCTAssertTrue(names.contains("analyze_local_image"), "registered tools: \(names)")
        print("AppContainer registered tools: \(names.joined(separator: ", "))")
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

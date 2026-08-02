#if os(macOS)
import XCTest
import FileViewerKit
@testable import Talkify

final class GitWorkingTreeReviewProviderTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorkingTreeReviewProviderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try runGit(["init", "-q"])
        try runGit(["config", "user.name", "Review Tests"])
        try runGit(["config", "user.email", "review@example.com"])
        try runGit(["config", "commit.gpgsign", "false"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testUnchangedLinesComeFromTheReviewedSnapshot() async throws {
        let fileURL = rootURL.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let originalLines = (1...20).map { "line \($0)" }
        try originalLines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Sources/App.swift"])
        try runGit(["commit", "-q", "-m", "initial"])

        var changedLines = originalLines
        changedLines[9] = "changed line 10"
        try changedLines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let changes = try await provider.workingTreeChanges()
        XCTAssertEqual(changes.map(\.filePath), ["Sources/App.swift"])

        // A later disk write must not change the context paired with the
        // already-rendered diff.
        try "completely different".write(to: fileURL, atomically: true, encoding: .utf8)
        let lines = try await provider.unchangedLines(
            for: "Sources/App.swift",
            startingAt: 1,
            count: 4
        )
        XCTAssertEqual(lines, Array(originalLines.prefix(4)))
    }

    func testInvalidOrMissingSnapshotRangeFails() async throws {
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        do {
            _ = try await provider.unchangedLines(for: "missing.swift", startingAt: 1, count: 1)
            XCTFail("Expected a stale snapshot error")
        } catch let error as FileReviewProviderError {
            guard case .staleSnapshot = error else {
                return XCTFail("Unexpected provider error: \(error)")
            }
        }
    }

    @discardableResult
    private func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootURL.path] + arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "GitWorkingTreeReviewProviderTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: errorData, as: UTF8.self)]
            )
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}
#endif

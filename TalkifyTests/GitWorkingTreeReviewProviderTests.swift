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

    private func write(_ path: String, _ text: String) throws {
        let url = rootURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func commitAll() throws { try runGit(["add", "--all"]); try runGit(["commit", "-q", "-m", "fixture"]) }

    func testUnbornAndNonGitAreDifferentFromCleanRepository() async throws {
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let unborn = try await provider.reviewSnapshot()
        XCTAssertEqual(unborn.state, .unborn)
        try write("new.swift", "hello\n")
        let first = try await provider.reviewSnapshot()
        XCTAssertEqual(first.files.first?.stateLabel, "未跟踪"); XCTAssertEqual(first.files.first?.added, 1)
        let nonGit = rootURL.appendingPathComponent("outside"); try FileManager.default.createDirectory(at: nonGit, withIntermediateDirectories: true)
        // A nested Git directory must be reported as a root mismatch, not clean.
        do { _ = try await GitWorkingTreeReviewProvider(rootURL: nonGit).reviewSnapshot(); XCTFail("nested root accepted") } catch {}
        let sibling = rootURL.deletingLastPathComponent().appendingPathComponent("ReviewPlain-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        let plain = GitWorkingTreeReviewProvider(rootURL: sibling)
        _ = try await plain.reviewObservation()
        let snapshot = try await plain.reviewSnapshot(); XCTAssertEqual(snapshot.state, .notGit)
    }
    func testSnapshotRetainsFileBytesAfterFurtherEditsAndRefresh() async throws {
        try write("a.swift", "before\n"); try commitAll(); try write("a.swift", "reviewed\n")
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let old = try await provider.reviewSnapshot()
        try write("a.swift", "later\n")
        let next = try await provider.reviewSnapshot()
        let oldDiff = try await provider.reviewChange(path: "a.swift", snapshotID: old.id)
        XCTAssertTrue(oldDiff.hunks.flatMap(\.lines).contains { if case .added("reviewed") = $0 { return true }; return false })
        let oldContext = try await provider.reviewContext(path: "a.swift", snapshotID: old.id, startLine: 1, count: 1)
        XCTAssertEqual(oldContext, ["reviewed"]); XCTAssertNotEqual(old.files.first?.revision, next.files.first?.revision)
    }
    func testRenameIsOneFileAndStagingDoesNotChangeDiffRevision() async throws {
        try write("old name.swift", "one\ntwo\nthree\n"); try commitAll()
        try runGit(["mv", "old name.swift", "new name.swift"])
        try write("new name.swift", "one\nchanged\nthree\n")
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let partial = try await provider.reviewSnapshot()
        XCTAssertEqual(partial.files.count, 1); XCTAssertEqual(partial.files[0].previousPath, "old name.swift")
        XCTAssertEqual(partial.files[0].path, "new name.swift")
        XCTAssertEqual(partial.files[0].added, 1); XCTAssertEqual(partial.files[0].removed, 1)
        try runGit(["add", "new name.swift"])
        let staged = try await provider.reviewSnapshot()
        XCTAssertEqual(staged.files[0].stateLabel, "R"); XCTAssertEqual(staged.files[0].revision, partial.files[0].revision)
        XCTAssertNotEqual(staged.id, partial.id)
    }
    func testPartialStagingFlagsAreKeptSeparateFromFinalDiff() async throws {
        try write("a.swift", "before\n"); try commitAll()
        try write("a.swift", "staged\n"); try runGit(["add", "a.swift"]); try write("a.swift", "working\n")
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let snapshot = try await provider.reviewSnapshot()
        XCTAssertEqual(snapshot.files[0].stateLabel, "部分暂存")
        let diff = try await provider.reviewChange(path: "a.swift", snapshotID: snapshot.id)
        let lines = diff.hunks.flatMap(\.lines)
        XCTAssertTrue(lines.contains { if case .added("working") = $0 { return true }; return false })
        XCTAssertFalse(lines.contains { if case .added("staged") = $0 { return true }; return false })
    }
    func testBranchSwitchAtSameCommitIsObservedWithoutChangingDiffIdentity() async throws {
        try write("a.txt", "before\n"); try commitAll(); try write("a.txt", "after\n")
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let before = try await provider.reviewObservation(); let old = try await provider.reviewSnapshot()
        try runGit(["checkout", "-q", "-b", "review-another-branch"])
        let after = try await provider.reviewObservation(); let next = try await provider.reviewSnapshot()
        XCTAssertNotEqual(before, after); XCTAssertEqual(old.id, next.id)
        XCTAssertEqual(next.branch, "review-another-branch")
    }
    func testStagedAdditionDeletedFromWorktreeDoesNotPretendToBeAnEmptyNewFile() async throws {
        try write("base.txt", "base\n"); try commitAll()
        try write("added.txt", "staged content\n"); try runGit(["add", "added.txt"])
        try FileManager.default.removeItem(at: rootURL.appendingPathComponent("added.txt"))
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let snapshot = try await provider.reviewSnapshot()
        let diff = try await provider.reviewChange(path: "added.txt", snapshotID: snapshot.id)
        XCTAssertTrue(diff.hunks.isEmpty); XCTAssertTrue(diff.summary.contains("暂存区与工作区"))
    }
    func testBinaryDeletedAndLargeFilesHaveHonestState() async throws {
        try write("deleted.txt", "old\n"); try commitAll()
        try FileManager.default.removeItem(at: rootURL.appendingPathComponent("deleted.txt"))
        try Data([0, 1, 2]).write(to: rootURL.appendingPathComponent("image.bin"))
        try Data(repeating: 65, count: 2 * 1024 * 1024 + 1).write(to: rootURL.appendingPathComponent("large.txt"))
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let snapshot = try await provider.reviewSnapshot()
        let deleted = try XCTUnwrap(snapshot.files.first { $0.path == "deleted.txt" })
        XCTAssertEqual(deleted.status, .deleted); XCTAssertEqual(deleted.removed, 1)
        let binary = try XCTUnwrap(snapshot.files.first { $0.path == "image.bin" })
        XCTAssertNil(binary.added); XCTAssertNotNil(binary.note)
        let large = try XCTUnwrap(snapshot.files.first { $0.path == "large.txt" }); XCTAssertNotNil(large.note)
        let diff = try await provider.reviewChange(path: "large.txt", snapshotID: snapshot.id)
        XCTAssertTrue(diff.hunks.isEmpty)
    }
    func testNoFinalNewlineUsesNativeGitCountsAndTabsInPathArePreserved() async throws {
        let path = "a\tname.txt"
        try write(path, "hello"); try commitAll(); try write(path, "hello\n")
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let snapshot = try await provider.reviewSnapshot()
        XCTAssertEqual(snapshot.files[0].path, path)
        XCTAssertEqual(snapshot.files[0].added, 1); XCTAssertEqual(snapshot.files[0].removed, 1)
        let diff = try await provider.reviewChange(path: path, snapshotID: snapshot.id)
        XCTAssertEqual(diff.addedLineCount, 1); XCTAssertEqual(diff.removedLineCount, 1)
    }
    func testConflictsAreNotRenderedAsOrdinarySuccessfulDiffs() async throws {
        try write("a.txt", "base\n"); try commitAll()
        let main = try runGit(["symbolic-ref", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["checkout", "-q", "-b", "side"]); try write("a.txt", "side\n"); try commitAll()
        try runGit(["checkout", "-q", main]); try write("a.txt", "main\n"); try commitAll()
        do { try runGit(["merge", "side"]); XCTFail("expected merge conflict") } catch {}
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let snapshot = try await provider.reviewSnapshot()
        XCTAssertTrue(snapshot.files[0].isConflict); XCTAssertNil(snapshot.files[0].added)
        let diff = try await provider.reviewChange(path: "a.txt", snapshotID: snapshot.id)
        XCTAssertTrue(diff.hunks.isEmpty); XCTAssertTrue(diff.summary.contains("冲突"))
    }
    func testSymlinkOutsideRepositoryNeverReadsTargetContents() async throws {
        let outside = rootURL.deletingLastPathComponent().appendingPathComponent("ReviewOutside-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("PRIVATE CONTENT".utf8).write(to: outside.appendingPathComponent("a.txt"))
        try write("folder/a.txt", "tracked\n"); try commitAll()
        try FileManager.default.removeItem(at: rootURL.appendingPathComponent("folder"))
        try FileManager.default.createSymbolicLink(at: rootURL.appendingPathComponent("folder"), withDestinationURL: outside)
        let provider = GitWorkingTreeReviewProvider(rootURL: rootURL)
        let snapshot = try await provider.reviewSnapshot()
        for file in snapshot.files {
            let diff = try await provider.reviewChange(path: file.path, snapshotID: snapshot.id)
            XCTAssertFalse(diff.hunks.flatMap(\.lines).map(\.text).joined().contains("PRIVATE CONTENT"))
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

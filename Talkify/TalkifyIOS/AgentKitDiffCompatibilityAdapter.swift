#if os(iOS)
import AgentKit
import FileViewerKit

/// The only remaining model boundary between AgentKit's legacy Inspector
/// protocol and FileViewerKit's canonical diff representation.
enum AgentKitDiffCompatibilityAdapter {
    static func content(
        original: String,
        modified: String,
        hunks canonicalHunks: [FileViewerKit.DiffHunk]
    ) -> AgentKit.DiffContent {
        let hunks = canonicalHunks.map { hunk in
            let lines = hunk.lines.map(agentLine)
            let oldCount = hunk.lines.filter {
                if case .added = $0 { return false }
                return true
            }.count
            let newCount = hunk.lines.filter {
                if case .removed = $0 { return false }
                return true
            }.count
            return AgentKit.DiffHunk(
                id: hunk.id,
                oldStart: hunk.oldStart,
                oldCount: oldCount,
                newStart: hunk.newStart,
                newCount: newCount,
                lines: lines
            )
        }

        return AgentKit.DiffContent(
            original: original,
            modified: modified,
            hunks: hunks
        )
    }

    private static func agentLine(_ line: FileViewerKit.DiffLine) -> AgentKit.DiffLine {
        switch line {
        case .unchanged(let text): .unchanged(text)
        case .added(let text): .added(text)
        case .removed(let text): .removed(text)
        }
    }
}
#endif

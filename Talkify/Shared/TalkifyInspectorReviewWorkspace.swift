#if os(macOS)
import SwiftUI
import FileViewerKit
import AgentKit

struct TalkifyInspectorReviewWorkspace: View {
    @Environment(WorkspaceStore.self) private var store
    private let session: FileReviewSession?
    private let selectedPath: Binding<String?>
    @State private var legacyProvider: GitWorkingTreeReviewProvider?

    init(session: FileReviewSession) {
        self.session = session; selectedPath = .constant(nil)
        _legacyProvider = State(initialValue: nil)
    }
    init(rootURL: URL, selectedPath: Binding<String?>) {
        session = nil; self.selectedPath = selectedPath
        _legacyProvider = State(initialValue: GitWorkingTreeReviewProvider(rootURL: rootURL))
    }
    var body: some View {
        Group {
            if let session {
                ReviewWorkspaceView(session: session, onOpenFile: openFile)
            } else if let legacyProvider {
                ReviewWorkspaceView(provider: legacyProvider, selectedPath: selectedPath, onOpenFile: openFile)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func openFile(_ path: String) { _ = store.openWorkspaceFile(path: path) }
}
#endif

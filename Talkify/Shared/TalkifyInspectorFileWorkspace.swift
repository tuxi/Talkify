import SwiftUI
import AgentKit
import FileViewerKit

/// FileViewerKit owns the editor and provider boundary; the host owns window chrome.
struct TalkifyInspectorFileWorkspace: View {
    let rootURL: URL
    private let session: FileWorkspaceSession?
    private let selectedPath: Binding<String?>
    @State private var provider: LocalFileContentProvider
    init(rootURL: URL, selectedPath: Binding<String?>) {
        self.rootURL = rootURL.standardizedFileURL; self.selectedPath = selectedPath; session = nil
        _provider = State(initialValue: LocalFileContentProvider(rootURL: rootURL))
    }
    init(session: FileWorkspaceSession) {
        self.session = session; rootURL = URL(fileURLWithPath: session.rootPath)
        selectedPath = .constant(nil)
        _provider = State(initialValue: LocalFileContentProvider(rootURL: rootURL))
    }
    var body: some View {
        if let session { FileWorkspaceView(session: session) }
        else {
            FileWorkspaceView(rootPath: rootURL.path, provider: provider, selectedPath: selectedPath,
                              textPreviewRenderer: { filePath, content, language in
                AnyView(AgentCodePreviewView(filePath: filePath, content: content, language: language))
            }).id(rootURL.path)
        }
    }
}

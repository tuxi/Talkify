#if os(macOS)
import SwiftUI
import FileViewerKit

struct TalkifyInspectorReviewWorkspace: View {
    let rootURL: URL
    @Binding var selectedPath: String?

    @State private var provider: GitWorkingTreeReviewProvider

    init(rootURL: URL, selectedPath: Binding<String?>) {
        let normalizedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        self.rootURL = normalizedRoot
        self._selectedPath = selectedPath
        self._provider = State(initialValue: GitWorkingTreeReviewProvider(rootURL: normalizedRoot))
    }

    var body: some View {
        ReviewWorkspaceView(provider: provider, selectedPath: $selectedPath)
            .id(rootURL.path)
    }
}
#endif

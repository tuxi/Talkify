import SwiftUI
import AgentKit
import FileViewerKit

/// FileViewerKit 负责文件树和多媒体分发；AgentKit 负责更强的代码文本预览。
struct TalkifyInspectorFileWorkspace: View {
    let rootURL: URL
    @Binding var selectedPath: String?

    @State private var provider: LocalFileContentProvider

    init(rootURL: URL, selectedPath: Binding<String?>) {
        let normalizedRoot = rootURL.standardizedFileURL
        self.rootURL = normalizedRoot
        self._selectedPath = selectedPath
        self._provider = State(
            initialValue: LocalFileContentProvider(rootURL: normalizedRoot)
        )
    }

    var body: some View {
        FileWorkspaceView(
            rootPath: rootURL.path,
            provider: provider,
            selectedPath: $selectedPath,
            textPreviewRenderer: { filePath, content, language in
                AnyView(
                    AgentCodePreviewView(
                        filePath: filePath,
                        content: content,
                        language: language
                    )
                )
            }
        )
        .id(rootURL.path)
    }
}

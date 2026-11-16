#if os(macOS)
import SwiftUI
import FileViewerKit

/// The shell owns one title row. Entry views own contextual controls and scrolling.
struct MacInspectorPaneHeader: View {
    let title: String
    let paneTitle: String
    let backLabel: String?
    let canReturnToRoot: Bool
    let isFocused: Bool
    let leadingInset: CGFloat
    let onBack: () -> Void
    let onRoot: () -> Void
    let onShowSidebar: () -> Void
    let onToggleFocus: () -> Void
    let onClose: () -> Void
    let onDrag: () -> Void
    var fileName: String? = nil
    var onCloseFile: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if isFocused {
                iconButton("显示侧栏", symbol: "sidebar.left", action: onShowSidebar)
            }
            if let backLabel {
                iconButton(backLabel, symbol: "chevron.left", action: onBack)
                    .accessibilityIdentifier("inspector.navigation.back")
            }
            Group {
                if let fileName, let onCloseFile {
                    HStack(spacing: 8) {
                        Text(fileName).font(.system(size: 13)).lineLimit(1).truncationMode(.middle).help(fileName)
                        Button(action: onCloseFile) { Image(systemName: "xmark").font(.system(size: 11)).frame(width: 20, height: 24) }
                            .buttonStyle(.plain).accessibilityLabel("关闭当前文件")
                    }.padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading).help(title).allowsHitTesting(false)
                }
            }
            if canReturnToRoot {
                Menu {
                    Button("返回根视图", systemImage: "arrow.uturn.backward", action: onRoot)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("详情导航")
            }
            iconButton(isFocused ? "还原对话布局" : "展开工具",
                       symbol: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       action: onToggleFocus)
            iconButton("关闭\(paneTitle)", symbol: "xmark", action: onClose)
                .accessibilityIdentifier("inspector.presentation.close")
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, 10)
        .frame(height: 46)
        .background(MacWorkspaceHeaderDragArea(onMouseDown: onDrag))
    }

    private func iconButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// No additional scroll view: file trees, diffs, web views and terminals own their viewport.
struct MacInspectorContentSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.workspacePresentation, .inspector)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipped()
            .accessibilityElement(children: .contain)
    }
}

struct MacInspectorStatusView: View {
    enum Status {
        case needsProject
        case unavailable(title: String, symbol: String)
    }
    let status: Status

    init(_ status: Status) { self.status = status }

    var body: some View {
        switch status {
        case .needsProject:
            WorkspaceStatusView("请先选择项目", symbol: "folder",
                                message: "选择工作目录后即可查看文件和变更。")
        case .unavailable(let title, let symbol):
            WorkspaceStatusView("\(title) 正在接入", symbol: symbol,
                                message: "当前阶段先完成工作区布局。")
        }
    }
}
#endif

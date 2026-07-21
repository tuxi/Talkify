//
//  WorkspaceHubView.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

#if os(iOS)
import SwiftUI
import AgentKit
import FileViewerKit

/// 抽屉内部的工作区枢纽视图。
///
/// 结构：
/// - WorkspaceHeader：当前工作区名 + 状态 + [›] 进入全屏浏览器
/// - Tab Segment：[💬 会话] [📄 快捷文件] [🔍 搜索]
/// - Content：根据 selectedTab 切换
/// - BottomBar：[💬 新对话] [⚙️ 设置]
struct WorkspaceHubView: View {

    @Environment(WorkspaceStore.self) private var store

    // MARK: - Bindings & Callbacks

    @Binding var selectedConversation: ConversationRef?
    let searchText: String
    let fileProvider: WorkspaceFileContentProvider?

    /// 用户点击 WorkspaceHeader 右侧 [›] → 父 VC present WorkspaceBrowser
    var onWorkspaceBrowserRequested: (() -> Void)?
    /// 新建对话 → store.beginDraft() + 关闭抽屉
    var onNewChat: (() -> Void)?
    /// 打开设置
    var onSettings: (() -> Void)?
    /// 预览文件 → 关闭抽屉 + 打开 FilePreviewHost
    var onFileSelected: ((String) -> Void)?

    // MARK: - Local State

    @State private var selectedTab: HubTab = .conversations

    enum HubTab: String, CaseIterable {
        case conversations
        case quickFiles
        case search

        var icon: String {
            switch self {
            case .conversations: return "bubble.left.and.bubble.right"
            case .quickFiles:    return "doc.text"
            case .search:        return "magnifyingglass"
            }
        }

        var title: String {
            switch self {
            case .conversations: return "会话"
            case .quickFiles:    return "文件"
            case .search:        return "搜索"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            tabBar
            tabContent
            bottomBar
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Workspace Header

    private var workspaceHeader: some View {
        Button {
            onWorkspaceBrowserRequested?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentWorkspaceName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    workspaceSubtitle
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看所有工作区")
    }

    private var currentWorkspaceName: String {
        if let conversation = store.selectedConversation, !conversation.workspacePath.isEmpty {
            return URL(fileURLWithPath: conversation.workspacePath).lastPathComponent
        }
        if let first = store.recentWorkspaces.workspaces.first {
            return first.name
        }
        return "工作区"
    }

    @ViewBuilder
    private var workspaceSubtitle: some View {
        let activeCount = activeConversationCount
        let workspaceCount = totalWorkspaceCount
        if activeCount > 0 || workspaceCount > 0 {
            HStack(spacing: 6) {
                if activeCount > 0 {
                    Label("\(activeCount) 活跃", systemImage: "circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
                if workspaceCount > 1 {
                    Text("\(workspaceCount) 个工作区")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var activeConversationCount: Int {
        store.listViewModel.conversations.filter {
            store.supervisor.activity(for: $0).isActive
        }.count
    }

    private var totalWorkspaceCount: Int {
        let recent = store.recentWorkspaces.workspaces.count
        let projects = store.projects.projects.count
        return max(recent, projects)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(HubTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .background(
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .conversations:
                ConversationListView(
                    viewModel: store.listViewModel,
                    selected: $selectedConversation,
                    searchText: searchText
                )
                .background(.ultraThinMaterial)

            case .quickFiles:
                ScrollView {
                    quickFilesTab
                }

            case .search:
                GlobalSearchPlaceholderView()
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Quick Files Tab

    @ViewBuilder
    private var quickFilesTab: some View {
        if let provider = fileProvider {
            let recentFiles = provider.recentChangedFiles()
            FileViewerKit.QuickFileList(
                recentlyChanged: recentFiles,
                pinnedFiles: [],
                onSelectFile: { path in
                    onFileSelected?(path)
                },
                onViewAll: { [self] in
                    onWorkspaceBrowserRequested?()
                }
            )
        } else {
            ContentUnavailableView(
                "文件浏览器不可用",
                systemImage: "doc.text.magnifyingglass",
                description: Text("未提供文件内容提供者")
            )
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                onNewChat?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                    Text("聊天")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            }

            Spacer(minLength: 30)

            Button {
                onSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 15)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Conversation Activity Helper

private extension ConversationActivityState {
    var isActive: Bool {
        switch self {
        case .running, .queued, .waitingForApproval, .waitingForClientTool, .connecting:
            return true
        case .idle, .succeeded, .failed, .cancelled, .paused:
            return false
        }
    }
}

// MARK: - Global Search Placeholder

private struct GlobalSearchPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "搜索",
            systemImage: "magnifyingglass",
            description: Text("跨会话和文件搜索即将上线")
        )
    }
}
#endif

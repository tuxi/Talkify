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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(WorkspaceStore.self) private var store

    // MARK: - Bindings & Callbacks

    @Binding var selectedConversation: ConversationRef?
    let searchText: String
    let fileProvider: WorkspaceFileContentProvider?
    let workspaceContext: IOSWorkspaceContext

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
    @State private var isWorkspaceSwitcherPresented = false

    enum HubTab: String, CaseIterable {
        case conversations
        case files
        case search

        var icon: String {
            switch self {
            case .conversations: return "bubble.left.and.bubble.right"
            case .files:         return "doc.text"
            case .search:        return "magnifyingglass"
            }
        }

        var title: String {
            switch self {
            case .conversations: return "会话"
            case .files:         return "文件"
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
                .safeAreaPadding(.bottom, 50)
        }
        .overlay(alignment: .bottom, content: {
            bottomBar
        })
        .sheet(isPresented: $isWorkspaceSwitcherPresented) {
            WorkspaceSwitcherView(
                workspaces: workspaceContext.availableWorkspaces(in: store),
                selectedWorkspaceID: workspaceContext.activeWorkspace?.id,
                onSelect: { workspace in
                    workspaceContext.activate(workspace, in: store)
                    isWorkspaceSwitcherPresented = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedConversation?.id) { _, _ in
            workspaceContext.synchronize(with: selectedConversation, in: store)
        }
    }

    // MARK: - Workspace Header

    private var workspaceHeader: some View {
        HStack(spacing: 8) {
            Button {
                isWorkspaceSwitcherPresented = true
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

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换项目")

            Button {
                onWorkspaceBrowserRequested?()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(workspaceContext.activeWorkspace == nil)
            .accessibilityLabel("查看当前项目")
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var currentWorkspaceName: String {
        workspaceContext.activeWorkspace?.name ?? "选择项目"
    }

    @ViewBuilder
    private var workspaceSubtitle: some View {
        let activeCount = activeConversationCount
        HStack(spacing: 5) {
            if let branch = workspaceContext.activeWorkspace?.branch {
                Text(branch)
            }
            if activeCount > 0 {
                if workspaceContext.activeWorkspace?.branch != nil { Text("·") }
                Text("\(activeCount) 个运行中")
                    .foregroundStyle(.green)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var activeConversationCount: Int {
        workspaceContext.conversations(in: store).filter {
            store.supervisor.activity(for: $0).isActive
        }.count
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
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .conversations:
                WorkspaceConversationListView(
                    store: store,
                    conversations: workspaceContext.conversations(in: store),
                    selected: $selectedConversation,
                    workspaceName: currentWorkspaceName,
                    workspaceGroupingID: workspaceContext.activeGroupingID
                )

            case .files:
                WorkspaceFilesView(
                    workspace: workspaceContext.activeWorkspace,
                    provider: fileProvider,
                    onSelectFile: { onFileSelected?($0) },
                    onOpenBrowser: { onWorkspaceBrowserRequested?() }
                )

            case .search:
                GlobalSearchView(
                    store: store,
                    fileProvider: fileProvider,
                    workspaceContext: workspaceContext,
                    onSelectConversation: { ref in
                        selectedConversation = ref
                    },
                    onSelectFile: { path in
                        onFileSelected?(path)
                    }
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bottom Bar
    private var bottomBar: some View {
        HStack {
            // "聊天" 按钮 - 药丸形状 (Capsule)
            Button {
                onNewChat?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                    Text("聊天")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                // 使用 accentColor，并加上阴影
                .background(Color.accentColor, in: Capsule())
                // **核心修改：添加阴影以增强层次感**
                // 根据颜色模式调整阴影颜色，确保在深色模式下也能清晰可见
                .shadow(color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.accentColor.opacity(0.2),
                        radius: 5, x: 0, y: 2)
            }

            Spacer(minLength: 30)

            // "设置" 按钮 - 圆形 (Circle)
            Button {
                onSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 40)
                    // 使用系统材质作为圆底，深色模式下会自动呈现出自带高级感的悬浮灰色
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            }
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 12)
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

// MARK: - Global Search

private struct WorkspaceSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    let workspaces: [Workspace]
    let selectedWorkspaceID: String?
    let onSelect: (Workspace) -> Void

    @State private var query = ""

    private var filteredWorkspaces: [Workspace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return workspaces }
        return workspaces.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.url.path.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredWorkspaces.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("项目") {
                        ForEach(filteredWorkspaces) { workspace in
                            Button {
                                onSelect(workspace)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(workspace.name)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let branch = workspace.branch {
                                            Label(branch, systemImage: "arrow.triangle.branch")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if workspace.id == selectedWorkspaceID {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索项目")
            .navigationTitle("切换项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct WorkspaceConversationListView: View {
    let store: WorkspaceStore
    let conversations: [ConversationRef]
    @Binding var selected: ConversationRef?
    let workspaceName: String
    let workspaceGroupingID: String?

    @State private var renameTarget: ConversationRef?
    @State private var renameText = ""
    @State private var deletionTarget: ConversationRef?
    @State private var forcedDeletionTarget: ConversationRef?
    @State private var forcedDeletionMessage = ""
    @State private var operationError: String?
    @State private var showsArchived = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(conversations.count) 个会话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.supportsConversationArchive {
                    Button {
                        showsArchived = true
                    } label: {
                        Label("已归档", systemImage: "archivebox")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            if conversations.isEmpty && !store.listViewModel.isLoading {
                ContentUnavailableView(
                    "还没有会话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("在 \(workspaceName) 中创建一个新对话")
                )
            } else {
                List(conversations, id: \.id) { conversation in
                    Button {
                        selected = conversation
                    } label: {
                        WorkspaceConversationRow(
                            conversation: conversation,
                            activity: store.supervisor.activity(for: conversation),
                            queueReason: store.supervisor.queueReason(for: conversation.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deletionTarget = conversation
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .disabled(!store.canDeleteConversation(conversation))

                        if store.supportsConversationArchive {
                            Button {
                                archive(conversation)
                            } label: {
                                Label("归档", systemImage: "archivebox")
                            }
                            .tint(.gray)
                            .disabled(!store.canArchiveConversation(conversation))
                        }
                    }
                    .contextMenu {
                        Button {
                            renameTarget = conversation
                            renameText = conversation.name ?? ""
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        if store.supportsConversationArchive {
                            Button {
                                archive(conversation)
                            } label: {
                                Label("归档", systemImage: "archivebox")
                            }
                            .disabled(!store.canArchiveConversation(conversation))
                        }
                        Divider()
                        Button(role: .destructive) {
                            deletionTarget = conversation
                        } label: {
                            Label("删除…", systemImage: "trash")
                        }
                        .disabled(!store.canDeleteConversation(conversation))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await store.listViewModel.refresh()
                    await store.refreshRuntimeState()
                }
            }
        }
        .task {
            await store.listViewModel.refresh()
            await store.refreshRuntimeState()
        }
        .sheet(isPresented: $showsArchived) {
            ArchivedWorkspaceConversationsView(
                store: store,
                workspaceGroupingID: workspaceGroupingID
            )
            .presentationDetents([.medium, .large])
        }
        .alert("重命名会话", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("会话名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("确定") { rename() }
        }
        .confirmationDialog(
            deletionTarget?.worktree?.managed == true ? "删除会话和 Worktree？" : "删除会话？",
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = deletionTarget {
                if target.worktree?.managed == true {
                    Button("仅删除会话，保留 Worktree", role: .destructive) {
                        delete(target, disposition: .keep)
                    }
                    Button("删除会话和 Worktree", role: .destructive) {
                        delete(target, disposition: .remove)
                    }
                } else {
                    Button("删除会话", role: .destructive) {
                        delete(target, disposition: .keep)
                    }
                }
                Button("取消", role: .cancel) { deletionTarget = nil }
            }
        } message: {
            Text(deletionTarget?.worktree?.managed == true
                 ? "删除 Worktree 前会执行安全检查，Git 分支不会被删除。"
                 : "此操作会永久删除会话及其历史。")
        }
        .alert(
            "Worktree 包含未保存的更改",
            isPresented: Binding(
                get: { forcedDeletionTarget != nil },
                set: { if !$0 { forcedDeletionTarget = nil } }
            )
        ) {
            Button("取消", role: .cancel) { forcedDeletionTarget = nil }
            Button("强制删除 Worktree 和会话", role: .destructive) {
                guard let target = forcedDeletionTarget else { return }
                forcedDeletionTarget = nil
                delete(target, disposition: .remove, force: true)
            }
        } message: {
            Text(forcedDeletionMessage)
        }
        .alert("操作失败", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("好", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "未知错误")
        }
    }

    private func rename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = renameTarget, !name.isEmpty else { return }
        renameTarget = nil
        Task {
            if let updated = await store.listViewModel.renameConversation(target, name: name),
               selected?.id == updated.id {
                selected = updated
            }
        }
    }

    private func archive(_ conversation: ConversationRef) {
        Task {
            do { _ = try await store.archiveConversation(conversation) }
            catch { operationError = error.localizedDescription }
        }
    }

    private func delete(
        _ conversation: ConversationRef,
        disposition: ConversationWorktreeDisposition,
        force: Bool = false
    ) {
        deletionTarget = nil
        Task {
            do {
                try await store.deleteConversation(
                    conversation,
                    worktreeDisposition: disposition,
                    forceWorktreeRemoval: force
                )
            } catch let error as ManagedWorktreeRemovalError
                where error.isDirtyConflict && !force {
                forcedDeletionTarget = conversation
                if let summary = error.summary {
                    forcedDeletionMessage = "检测到 \(summary.modifiedFiles) 个已修改文件、\(summary.untrackedFiles) 个未跟踪文件和 \(summary.newCommits) 个新提交。强制删除会永久移除 checkout，但保留 Git 分支。"
                } else {
                    forcedDeletionMessage = "Runtime 检测到可能丢失的更改。强制删除会永久移除 checkout，但保留 Git 分支。"
                }
            } catch {
                operationError = error.localizedDescription
            }
        }
    }
}

private struct WorkspaceConversationRow: View {
    let conversation: ConversationRef
    let activity: ConversationActivityState
    let queueReason: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activityIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(activityColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.name ?? conversation.id)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var detailText: String? {
        if let queueReason, !queueReason.isEmpty { return queueReason }
        if let worktree = conversation.worktree { return worktree.branch }
        switch activity {
        case .running: return "正在运行"
        case .waitingForApproval: return "等待批准"
        case .waitingForClientTool: return "等待设备操作"
        case .queued: return "已排队"
        case .connecting: return "正在连接"
        case .paused: return "已暂停"
        case .failed: return "运行失败"
        default: return nil
        }
    }

    private var activityIcon: String {
        switch activity {
        case .running, .connecting: return "circle.dotted"
        case .queued: return "clock"
        case .waitingForApproval, .waitingForClientTool: return "exclamationmark.circle.fill"
        case .paused: return "pause.circle"
        case .succeeded: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .cancelled: return "slash.circle"
        case .idle: return "bubble.left"
        }
    }

    private var activityColor: Color {
        switch activity {
        case .running, .connecting, .queued: return .blue
        case .waitingForApproval, .waitingForClientTool: return .orange
        case .failed: return .red
        case .succeeded: return .green
        default: return .secondary
        }
    }
}

private struct ArchivedWorkspaceConversationsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let workspaceGroupingID: String?
    @State private var errorMessage: String?

    private var conversations: [ConversationRef] {
        guard let workspaceGroupingID else { return [] }
        return store.listViewModel.archivedConversations.filter {
            $0.workspaceGroupingID == workspaceGroupingID
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView("暂无归档会话", systemImage: "archivebox")
                } else {
                    List(conversations, id: \.id) { conversation in
                        HStack {
                            Text(conversation.name ?? conversation.id).lineLimit(1)
                            Spacer()
                            Button("恢复") { restore(conversation) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("已归档")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await store.listViewModel.refreshArchived() }
            .alert("恢复失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func restore(_ conversation: ConversationRef) {
        Task {
            do { _ = try await store.restoreConversation(conversation) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct WorkspaceFilesView: View {
    let workspace: Workspace?
    let provider: WorkspaceFileContentProvider?
    let onSelectFile: (String) -> Void
    let onOpenBrowser: () -> Void

    @State private var directoryPath = ""
    @State private var directoryTitles: [String] = []
    @State private var directoryPaths: [String] = []
    @State private var nodes: [WorkspaceFileListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if directoryPaths.count > 1 {
                    Button { navigateBack() } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                Text(directoryTitles.last ?? workspace?.name ?? "文件")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onOpenBrowser) {
                    Label("完整浏览", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let errorMessage {
                ContentUnavailableView(
                    "无法读取文件",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if nodes.isEmpty {
                ContentUnavailableView("没有文件", systemImage: "folder")
            } else {
                List(nodes) { node in
                    Button {
                        if node.isDirectory { navigateInto(node) }
                        else { onSelectFile(node.path) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: node.isDirectory ? "folder" : node.systemImageName)
                                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
                                .frame(width: 22)
                            Text(node.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if node.isDirectory {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .refreshable { await loadDirectory() }
            }
        }
        .task(id: workspace?.id) {
            guard let workspace else { return }
            directoryPath = workspace.url.path
            directoryPaths = [workspace.url.path]
            directoryTitles = [workspace.name]
            await loadDirectory()
        }
    }

    private func navigateInto(_ node: WorkspaceFileListItem) {
        directoryPath = node.path
        directoryPaths.append(node.path)
        directoryTitles.append(node.name)
        Task { await loadDirectory() }
    }

    private func navigateBack() {
        guard directoryPaths.count > 1 else { return }
        directoryPaths.removeLast()
        directoryTitles.removeLast()
        directoryPath = directoryPaths.last ?? workspace?.url.path ?? ""
        Task { await loadDirectory() }
    }

    private func loadDirectory() async {
        guard let provider, !directoryPath.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            nodes = try await provider.children(of: directoryPath).map(WorkspaceFileListItem.init)
        } catch {
            nodes = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct WorkspaceFileListItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let systemImageName: String

    init(_ node: any FileViewerKit.FileNode) {
        id = node.id
        name = node.name
        path = node.path
        isDirectory = node.isDirectory
        systemImageName = node.systemImageName
    }
}

private struct GlobalSearchView: View {

    let store: WorkspaceStore
    let fileProvider: WorkspaceFileContentProvider?
    let workspaceContext: IOSWorkspaceContext
    var onSelectConversation: ((ConversationRef) -> Void)?
    var onSelectFile: ((String) -> Void)?

    @State private var query = ""
    @State private var fileResults: [any FileViewerKit.FileNode] = []

    private var conversationResults: [ConversationRef] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return workspaceContext.conversations(in: store).filter { ref in
            (ref.name ?? "").localizedCaseInsensitiveContains(q) ||
            ref.id.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索会话或文件...", text: $query)
                    .textFieldStyle(.plain)
                    .onChange(of: query) { _, newValue in
                        searchFiles(newValue)
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        fileResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Results
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
            } else if conversationResults.isEmpty && fileResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if !conversationResults.isEmpty {
                        Section("会话") {
                            ForEach(conversationResults) { ref in
                                Button {
                                    onSelectConversation?(ref)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "bubble.left")
                                            .foregroundStyle(.secondary)
                                        Text(ref.name ?? ref.id)
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }

                    if !fileResults.isEmpty {
                        Section("文件") {
                            ForEach(fileResults, id: \.id) { file in
                                Button {
                                    onSelectFile?(file.path)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: file.systemImageName)
                                            .foregroundStyle(.secondary)
                                        Text(file.name)
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func searchFiles(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let provider = fileProvider else {
            fileResults = []
            return
        }
        fileResults = provider.searchFiles(matching: trimmed)
    }
}
#endif

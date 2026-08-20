//
//  WorkspaceHubView.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AgentKit
import FileViewerKit
import CoreKit

/// 抽屉内部的工作区枢纽视图。
///
/// 结构：
/// - WorkspaceHeader：切换当前项目 + 独立入口进入完整浏览器
/// - Tab Segment：[💬 会话] [📄 文件] [🔍 搜索]
/// - Content：根据 selectedTab 切换
/// - BottomBar：[💬 新对话] [⚙️ 设置]
struct WorkspaceHubView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppContainer.self) private var container

    // MARK: - Bindings & Callbacks

    @Binding var selectedConversation: ConversationRef?
    let searchText: String
    let fileProvider: WorkspaceFileContentProvider?
    let workspaceContext: IOSWorkspaceContext
    let isBottomHide: Bool

    /// 用户点击 WorkspaceHeader 右侧 [›] → 父 VC present WorkspaceBrowser
    var onWorkspaceBrowserRequested: (() -> Void)?
    /// 新建对话 → store.beginDraft() + 关闭抽屉
    var onNewChat: (() -> Void)?
    /// 打开设置
    var onSettings: ((SettingsSection) -> Void)?
    /// 预览文件 → 关闭抽屉 + 打开 FilePreviewHost
    var onFileSelected: ((String) -> Void)?
    /// 工作区 ZIP 准备完成 → 由宿主展示系统分享面板
    var onWorkspaceExportReady: ((URL) -> Void)?
    
    
    var tabs: [HubTab] {
        if workspaceContext.isExternalServer {
            return [
                .conversations,
                .search
            ]
        }
        if DeviceInfo.isPadLayout {
            return [
                .conversations,
                .files
            ]
        }
        return HubTab.allCases
    }

    // MARK: - Local State

    @State private var selectedTab: HubTab = .conversations
    @State private var isWorkspaceSwitcherPresented = false
    @State private var isNewWorkspacePresented = false
    @State private var newWorkspaceName = "New Project"
    @State private var isImporterPresented = false
    @State private var isWorkspaceContentImporterPresented = false
    @State private var isImportingWorkspaceContent = false
    @State private var workspaceFilesRevision = 0
    @State private var fileNavigationStates: [String: WorkspaceFileNavigationState] = [:]
    @State private var isExportingWorkspace = false
    @State private var workspaceExportError: String?
    @State private var pendingImportURL: URL?
    @State private var importName = ""
    @State private var isImportNamePresented = false
    @State private var isGitClonePresented = false
    @State private var pendingAcquisitionAction: WorkspaceAcquisitionAction?
    @State private var acquisitionError: String?
    @Namespace private var tabSelectionNamespace

    private enum WorkspaceAcquisitionAction {
        case create
        case importFolder
        case cloneGit
    }

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
            case .conversations: return TalkifyLocalized.string("workspace.tab.conversations")
            case .files:         return TalkifyLocalized.string("workspace.tab.files")
            case .search:        return TalkifyLocalized.string("workspace.tab.search")
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if workspaceContext.activeSelection == nil,
               workspaceContext.isExternalServer {
                externalServerEmptyState
            } else if workspaceContext.activeSelection == nil {
                WorkspaceProjectLauncher(
                    canImport: store.projects.isAvailable,
                    canClone: store.supportsPublicGitClone,
                    isPreparing: store.isPreparingWorkspace,
                    onCreate: { requestAcquisition(.create) },
                    onImport: { requestAcquisition(.importFolder) },
                    onClone: { requestAcquisition(.cloneGit) },
                    onSettings: { onSettings?(.account) }
                )
            } else {
                VStack(spacing: 0) {
                    workspaceHeader
                    tabBar
                    tabContent
                        .safeAreaPadding(.bottom, 68)
                }
                .overlay(alignment: .bottom, content: {
                    if !isBottomHide {
                        bottomBar
                            .safeAreaPadding()
                        
                    }
                    
                })
            }
        }
        .sheet(isPresented: $isWorkspaceSwitcherPresented) {
            WorkspaceSwitcherView(
                selections: workspaceContext.availableSelections(in: store),
                selectedSelectionID: workspaceContext.activeSelection?.id,
                onSelect: { selection in
                    workspaceContext.activate(selection, in: store)
                    isWorkspaceSwitcherPresented = false
                },
                onCreate: workspaceContext.isExternalServer
                    ? nil
                    : { requestAcquisition(.create) },
                onImport: workspaceContext.isExternalServer
                    ? nil
                    : { requestAcquisition(.importFolder) },
                onClone: !workspaceContext.isExternalServer && store.supportsPublicGitClone
                    ? { requestAcquisition(.cloneGit) }
                    : nil
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isGitClonePresented) {
            WorkspaceGitCloneSheet(
                projectsRoot: store.runtimeProjectsRoot,
                onCancel: { isGitClonePresented = false },
                onClone: cloneWorkspace
            )
            .interactiveDismissDisabled(store.isPreparingWorkspace)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .fileImporter(
            isPresented: $isWorkspaceContentImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleWorkspaceContentImport
        )
        .alert(TalkifyLocalized.string("workspace.new_workspace"), isPresented: $isNewWorkspacePresented) {
            TextField(TalkifyLocalized.string("share.workspace_name"), text: $newWorkspaceName)
            Button(TalkifyLocalized.string("common.action.cancel"), role: .cancel) { }
            Button(TalkifyLocalized.string("workspace.create")) { createWorkspace() }
                .disabled(newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(TalkifyLocalized.string("workspace.create_blank_hint"))
        }
        .alert(TalkifyLocalized.string("workspace.import_workspace"), isPresented: $isImportNamePresented) {
            TextField(TalkifyLocalized.string("share.workspace_name"), text: $importName)
            Button(TalkifyLocalized.string("common.action.cancel"), role: .cancel) { pendingImportURL = nil }
            Button(TalkifyLocalized.string("workspace.import_action")) { importWorkspace() }
                .disabled(importName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(verbatim: TalkifyLocalized.string("workspace.folder_will_be_copied"))
        }
        .alert(TalkifyLocalized.string("workspace.cannot_prepare"), isPresented: Binding(
            get: { acquisitionError != nil },
            set: { if !$0 { acquisitionError = nil } }
        )) {
            Button(TalkifyLocalized.string("workspace.ok"), role: .cancel) { acquisitionError = nil }
        } message: {
            Text(acquisitionError ?? TalkifyLocalized.string("common.error.unknown"))
        }
        .alert(TalkifyLocalized.string("workspace.cannot_export"), isPresented: Binding(
            get: { workspaceExportError != nil },
            set: { if !$0 { workspaceExportError = nil } }
        )) {
            Button(TalkifyLocalized.string("workspace.ok"), role: .cancel) { workspaceExportError = nil }
        } message: {
            Text(workspaceExportError ?? TalkifyLocalized.string("common.error.unknown"))
        }
        .onAppear {
            if !workspaceContext.isExternalServer {
                store.projects.reload()
            }
            workspaceContext.reconcile(in: store)
            if workspaceContext.activeSelection == nil,
               !workspaceContext.isExternalServer {
                store.beginDraft()
                workspaceContext.synchronize(with: nil, in: store)
            }
        }
        .onChange(of: isWorkspaceSwitcherPresented) { _, isPresented in
            guard !isPresented, let action = pendingAcquisitionAction else { return }
            pendingAcquisitionAction = nil
            Task { @MainActor in
                await Task.yield()
                presentAcquisition(action)
            }
        }
        .onChange(of: selectedConversation?.id) { _, _ in
            workspaceContext.synchronize(with: selectedConversation, in: store)
        }
        .onChange(of: store.listViewModel.revision, initial: true) { _, _ in
            workspaceContext.reconcile(in: store)
        }
    }

    // MARK: - Workspace Acquisition

    private func requestAcquisition(_ action: WorkspaceAcquisitionAction) {
        if isWorkspaceSwitcherPresented {
            pendingAcquisitionAction = action
            isWorkspaceSwitcherPresented = false
        } else {
            presentAcquisition(action)
        }
    }

    private func presentAcquisition(_ action: WorkspaceAcquisitionAction) {
        switch action {
        case .create:
            newWorkspaceName = "New Project"
            isNewWorkspacePresented = true
        case .importFolder:
            isImporterPresented = true
        case .cloneGit:
            isGitClonePresented = true
        }
    }

    private func createWorkspace() {
        do {
            store.beginDraft()
            try store.createAndSelectProject(named: newWorkspaceName)
            finishWorkspaceAcquisition(opensComposer: true)
        } catch {
            acquisitionError = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            pendingImportURL = url
            importName = ProjectsStore.suggestedName(forImporting: url)
            isImportNamePresented = true
        case .failure(let error):
            let nsError = error as NSError
            guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) else {
                return
            }
            acquisitionError = error.localizedDescription
        }
    }

    private func importWorkspace() {
        guard let sourceURL = pendingImportURL else { return }
        pendingImportURL = nil
        let name = importName
        Task {
            do {
                store.beginDraft()
                try await store.importAndSelectProject(from: sourceURL, named: name)
                finishWorkspaceAcquisition(opensComposer: true)
            } catch {
                acquisitionError = error.localizedDescription
            }
        }
    }

    private func handleWorkspaceContentImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty, let fileProvider else { return }
            isImportingWorkspaceContent = true
            Task {
                defer { isImportingWorkspaceContent = false }
                do {
                    try await fileProvider.importItems(urls)
                    workspaceFilesRevision += 1
                } catch {
                    acquisitionError = error.localizedDescription
                }
            }
        case .failure(let error):
            let nsError = error as NSError
            guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) else {
                return
            }
            acquisitionError = error.localizedDescription
        }
    }

    private func cloneWorkspace(_ request: PublicGitCloneRequest) async throws {
        store.beginDraft()
        try await store.cloneAndSelectProject(request: request)
        isGitClonePresented = false
        finishWorkspaceAcquisition(opensComposer: true)
    }

    private func finishWorkspaceAcquisition(opensComposer: Bool) {
        workspaceContext.synchronize(with: nil, in: store)
        guard opensComposer else { return }
        onNewChat?()
    }

    private func exportWorkspace() {
        guard !isExportingWorkspace, let fileProvider else { return }
        isExportingWorkspace = true
        workspaceExportError = nil
        Task {
            defer { isExportingWorkspace = false }
            do {
                let archiveURL = try await fileProvider.exportWorkspaceArchive()
                onWorkspaceExportReady?(archiveURL)
            } catch is CancellationError {
                return
            } catch {
                workspaceExportError = error.localizedDescription
            }
        }
    }

    // MARK: - Workspace Header

    private var workspaceHeader: some View {
        HStack(spacing: 10) {
            Button {
                isWorkspaceSwitcherPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(
                            Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(currentWorkspaceName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        workspaceSubtitle
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    if !workspaceContext.isExternalServer {
                        Button {
                            exportWorkspace()
                        } label: {
                            HStack {
                                Group {
                                    if isExportingWorkspace {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(.secondary)
                                .frame(width: 38, height: 38)
                                .background(
                                    Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                                }
                                Text(isExportingWorkspace ? TalkifyLocalized.string("workspace.exporting_project") : TalkifyLocalized.string("workspace.export_project"))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isExportingWorkspace || fileProvider == nil)
                        .accessibilityLabel(isExportingWorkspace ? TalkifyLocalized.string("workspace.exporting_project") : TalkifyLocalized.string("workspace.export_project"))
                        Divider()
                        Button {
                            onWorkspaceBrowserRequested?()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                                    }
                                Text(TalkifyLocalized.string("workspace.view_current_project"))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(workspaceContext.activeWorkspace == nil)
                        .accessibilityLabel(TalkifyLocalized.string("workspace.view_current_project"))
                    } else {
                        Button {
                            onSettings?(.servers)
                        } label: {
                            Label(
                                TalkifyLocalized.string("打开服务器设置"),
                                systemImage: "server.rack"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TalkifyLocalized.string("workspace.switch_project"))

        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 13)
        .background(Color.primary.opacity(0.012))
    }

    private var currentWorkspaceName: String {
        workspaceContext.activeDisplayName
            ?? TalkifyLocalized.string("workspace.select_project")
    }

    @ViewBuilder
    private var workspaceSubtitle: some View {
        HStack(spacing: 6) {
            if let branch = workspaceContext.activeWorkspace?.branch {
                Label(branch, systemImage: "arrow.triangle.branch")
            }
            if let workspaceStatus {
                if workspaceContext.activeWorkspace?.branch != nil {
                    Text("·").foregroundStyle(.tertiary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(workspaceStatus.color)
                        .frame(width: 5, height: 5)
                    Text(workspaceStatus.title)
                }
            } else if workspaceContext.isExternalServer {
                Text(verbatim: container.runtimeServers.activeConnection.displayName)
            } else if workspaceContext.activeWorkspace?.branch == nil {
                Text(verbatim: TalkifyLocalized.string("workspace.local_workspace"))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var workspaceStatus: (title: String, color: Color)? {
        let conversations = workspaceContext.conversations(in: store)
        let waitingCount = conversations.filter {
            let activity = store.supervisor.activity(for: $0)
            return activity == .waitingForApproval || activity == .waitingForClientTool
        }.count
        if waitingCount > 0 {
            return (String(format: TalkifyLocalized.string("workspace.pending_count"), String(waitingCount)), .orange)
        }

        let activeCount = conversations.filter {
            store.supervisor.activity(for: $0).isActive
        }.count
        if activeCount > 0 {
            return (String(format: TalkifyLocalized.string("workspace.running_count"), String(activeCount)), .green)
        }
        if store.draft != nil {
            return (TalkifyLocalized.string("workspace.draft"), .orange)
        }
        return nil
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.04)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
                                .matchedGeometryEffect(
                                    id: "workspace-hub-tab-selection",
                                    in: tabSelectionNamespace
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Color.primary.opacity(colorScheme == .dark ? 0.065 : 0.045),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
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
                    workspaceGroupingID: workspaceContext.activeGroupingID,
                    onCreateConversation: { onNewChat?() }
                )

            case .files:
                WorkspaceFilesView(
                    workspace: workspaceContext.activeWorkspace,
                    provider: fileProvider,
                    navigationState: fileNavigationBinding(for: workspaceContext.activeWorkspace),
                    refreshRevision: workspaceFilesRevision,
                    isImporting: isImportingWorkspaceContent,
                    onSelectFile: { onFileSelected?($0) },
                    onOpenBrowser: { onWorkspaceBrowserRequested?() },
                    onStartConversation: { onNewChat?() },
                    onImportItems: { isWorkspaceContentImporterPresented = true }
                )

            case .search:
                GlobalSearchView(
                    store: store,
                    fileProvider: workspaceContext.isExternalServer ? nil : fileProvider,
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
        .id(selectedTab)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.16), value: selectedTab)
        .frame(maxHeight: .infinity)
    }

    private var externalServerEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("当前服务器暂无工作区")
                    .font(.headline)
                Text("在 Mac 上创建会话后，工作区和对话会显示在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                onSettings?(.servers)
            } label: {
                Label(
                    TalkifyLocalized.string("打开服务器设置"),
                    systemImage: "gearshape"
                )
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(24)
    }

    private func fileNavigationBinding(for workspace: Workspace?) -> Binding<WorkspaceFileNavigationState> {
        let key = workspace?.id ?? "none"
        return Binding(
            get: {
                fileNavigationStates[key]
                    ?? WorkspaceFileNavigationState.root(for: workspace)
            },
            set: { fileNavigationStates[key] = $0 }
        )
    }

    // MARK: - Bottom Bar
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if container.runtimeServers.activeConnection.kind != .embedded {
                ActiveRuntimeServerIndicator(style: .sidebar) {
                    onSettings?(.servers)
                }
            }

            HStack(spacing: 10) {
                Button {
                    onNewChat?()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.pencil")
                        Text(store.draft == nil ? TalkifyLocalized.string("workspace.new_conversation") : TalkifyLocalized.string("workspace.continue_draft"))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        Color.accentColor,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .shadow(color: Color.accentColor.opacity(0.18), radius: 8, y: 3)
                }
                .buttonStyle(.plain)

                Button {
                    onSettings?(.account)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, height: 42)
                        .background(
                            Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.055),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TalkifyLocalized.string("workspace.settings"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
//        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
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
    let selections: [IOSWorkspaceContext.Selection]
    let selectedSelectionID: String?
    let onSelect: (IOSWorkspaceContext.Selection) -> Void
    let onCreate: (() -> Void)?
    let onImport: (() -> Void)?
    let onClone: (() -> Void)?

    @State private var query = ""

    private var filteredSelections: [IOSWorkspaceContext.Selection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return selections }
        return selections.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.workspace?.url.path.localizedCaseInsensitiveContains(trimmed) == true)
        }
    }

    var body: some View {
        NavigationStack {
            List {

                if filteredSelections.isEmpty {
                    if !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                } else {
                    Section(TalkifyLocalized.string("workspace.projects_section")) {
                        ForEach(filteredSelections) { selection in
                            Button {
                                onSelect(selection)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            Color.accentColor.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selection.displayName)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let branch = selection.workspace?.branch,
                                           !branch.isEmpty {
                                            Label(branch, systemImage: "arrow.triangle.branch")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else if selection.isServerDerived,
                                                  let path = selection.workspace?.url.path {
                                            Text(path)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if selection.id == selectedSelectionID {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                selection.id == selectedSelectionID
                                    ? Color.accentColor.opacity(0.07)
                                    : Color.clear
                            )
                        }
                    }
                }
                if onCreate != nil || onImport != nil || onClone != nil {
                    Section(TalkifyLocalized.string("workspace.add_workspace_section")) {
                        if let onCreate {
                            Button(action: onCreate) {
                                Label(TalkifyLocalized.string("workspace.new_blank_workspace"), systemImage: "folder.badge.plus")
                            }
                        }
                        if let onImport {
                            Button(action: onImport) {
                                Label(TalkifyLocalized.string("workspace.import_from_files"), systemImage: "square.and.arrow.down")
                            }
                        }
                        if let onClone {
                            Button(action: onClone) {
                                Label(TalkifyLocalized.string("workspace.clone_git_repo"), systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: TalkifyLocalized.string("workspace.search_projects"))
            .navigationTitle(TalkifyLocalized.string("workspace.switch_project_nav"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(TalkifyLocalized.string("workspace.done")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - First-run Workspace Launcher

private struct WorkspaceProjectLauncher: View {
    @Environment(\.colorScheme) private var colorScheme

    let canImport: Bool
    let canClone: Bool
    let isPreparing: Bool
    let onCreate: () -> Void
    let onImport: () -> Void
    let onClone: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CodeAgent")
                        .font(.system(size: 17, weight: .semibold))
                    Text(TalkifyLocalized.string("workspace.create_first"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(
                            Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TalkifyLocalized.string("workspace.settings"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: "folder.fill.badge.plus")
                            .font(.system(size: 29, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 58, height: 58)
                            .background(
                                Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.11),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )

                        Text(verbatim: TalkifyLocalized.string("workspace.start_from_idea"))
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text(verbatim: TalkifyLocalized.string("workspace.start_from_idea_desc"))
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onCreate) {
                        Label(TalkifyLocalized.string("workspace.create_blank_action"), systemImage: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(
                                Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: TalkifyLocalized.string("workspace.or_start_from_existing"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        if canClone {
                            launcherOption(
                                title: TalkifyLocalized.string("workspace.clone_git_repo_title"),
                                subtitle: TalkifyLocalized.string("workspace.clone_git_repo_subtitle"),
                                icon: "arrow.down.circle",
                                action: onClone
                            )
                        }

                        if canImport {
                            launcherOption(
                                title: TalkifyLocalized.string("workspace.import_folder_title"),
                                subtitle: "从“文件”App 复制现有项目",
                                icon: "square.and.arrow.down",
                                action: onImport
                            )
                        }
                    }

                    Text(verbatim: TalkifyLocalized.string("workspace.saved_on_iphone"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 40)
                .padding(.bottom, 28)
            }

            if isPreparing {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(TalkifyLocalized.string("workspace.preparing"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 14)
            }
        }
    }

    private func launcherOption(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.09),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.065 : 0.035),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
    }
}

private struct WorkspaceGitCloneSheet: View {
    let projectsRoot: String?
    let onCancel: () -> Void
    let onClone: (PublicGitCloneRequest) async throws -> Void

    @State private var repositoryURL = ""
    @State private var branch = ""
    @State private var projectName = ""
    @State private var clonesFullHistory = false
    @State private var isCloning = false
    @State private var errorMessage: String?

    private var trimmedURL: String {
        repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(TalkifyLocalized.string("workspace.public_git_repo_section")) {
                    TextField("https://github.com/owner/repo.git", text: $repositoryURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField(TalkifyLocalized.string("workspace.branch_or_tag_optional"), text: $branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(TalkifyLocalized.string("workspace.name_optional"), text: $projectName)
                }

                Section {
                    Toggle(TalkifyLocalized.string("workspace.clone_full_history"), isOn: $clonesFullHistory)
                } footer: {
                    Text(verbatim: TalkifyLocalized.string("workspace.clone_default_desc"))
                }

                if let projectsRoot {
                    Section(TalkifyLocalized.string("workspace.save_location_section")) {
                        Text(projectsRoot)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(TalkifyLocalized.string("workspace.clone_git_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TalkifyLocalized.string("common.action.cancel"), action: onCancel)
                        .disabled(isCloning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCloning ? TalkifyLocalized.string("workspace.cloning") : TalkifyLocalized.string("workspace.clone_action")) { startClone() }
                        .disabled(trimmedURL.isEmpty || isCloning)
                }
            }
        }
    }

    private func startClone() {
        guard !trimmedURL.isEmpty, !isCloning else { return }
        isCloning = true
        errorMessage = nil
        let request = PublicGitCloneRequest(
            requestID: UUID().uuidString,
            url: trimmedURL,
            ref: branch,
            name: projectName,
            depth: clonesFullHistory ? 0 : 1
        )
        Task {
            do {
                try await onClone(request)
            } catch {
                errorMessage = error.localizedDescription
                isCloning = false
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
    let onCreateConversation: () -> Void

    @State private var renameTarget: ConversationRef?
    @State private var renameText = ""
    @State private var deletionTarget: ConversationRef?
    @State private var forcedDeletionTarget: ConversationRef?
    @State private var forcedDeletionMessage = ""
    @State private var operationError: String?
    @State private var showsArchived = false

    private var conversationItems: [ConversationListItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: store.listViewModel.conversationItems.map {
            ($0.id, $0)
        })
        return conversations.compactMap { itemsByID[$0.id] }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(format: TalkifyLocalized.string("workspace.conversations_count"), String(conversations.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.supportsConversationArchive {
                    Button {
                        showsArchived = true
                    } label: {
                        Label(TalkifyLocalized.string("workspace.archived_label"), systemImage: "archivebox")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            if conversations.isEmpty && !store.listViewModel.isLoading {
                ScrollView {
                    WorkspaceSectionEmptyState(
                        icon: "bubble.left.and.bubble.right",
                        title: TalkifyLocalized.string("workspace.start_first_conversation"),
                        description: String(format: TalkifyLocalized.string("workspace.start_first_conversation_desc"), workspaceName),
                        primaryTitle: TalkifyLocalized.string("workspace.start_conversation"),
                        primaryIcon: "square.and.pencil",
                        primaryAction: onCreateConversation
                    )
                }
                .scrollIndicators(.hidden, axes: .vertical)
            } else {
                List(conversationItems) { item in
                    let conversation = item.ref
                    Button {
                        selected = conversation
                    } label: {
                        WorkspaceConversationRow(
                            conversation: item,
                            activity: store.supervisor.activity(for: conversation),
                            queueReason: store.supervisor.queueReason(for: conversation.id),
                            isSelected: selected?.id == conversation.id
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(top: 1, leading: 12, bottom: 1, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deletionTarget = conversation
                        } label: {
                            Label(TalkifyLocalized.string("common.action.delete"), systemImage: "trash")
                        }
                        .disabled(!store.canDeleteConversation(conversation))

                        if store.supportsConversationArchive {
                            Button {
                                archive(conversation)
                            } label: {
                                Label(TalkifyLocalized.string("workspace.archive"), systemImage: "archivebox")
                            }
                            .tint(.gray)
                            .disabled(!store.canArchiveConversation(conversation))
                        }
                    }
                    .contextMenu {
                        Button {
                            beginRename(conversationID: conversation.id, fallback: conversation)
                        } label: {
                            Label(TalkifyLocalized.string("workspace.rename"), systemImage: "pencil")
                        }
                        if store.supportsConversationArchive {
                            Button {
                                archive(conversation)
                            } label: {
                                Label(TalkifyLocalized.string("workspace.archive"), systemImage: "archivebox")
                            }
                            .disabled(!store.canArchiveConversation(conversation))
                        }
                        Divider()
                        Button(role: .destructive) {
                            deletionTarget = conversation
                        } label: {
                            Label(TalkifyLocalized.string("workspace.delete_with_ellipsis"), systemImage: "trash")
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
        .alert(TalkifyLocalized.string("workspace.rename_conversation"), isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField(TalkifyLocalized.string("workspace.conversation_name"), text: $renameText)
            Button(TalkifyLocalized.string("common.action.cancel"), role: .cancel) { renameTarget = nil }
            Button(TalkifyLocalized.string("workspace.confirm")) { rename() }
        }
        .confirmationDialog(
            deletionTarget?.worktree?.managed == true ? TalkifyLocalized.string("workspace.delete_conversation_and_worktree") : TalkifyLocalized.string("workspace.delete_conversation"),
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

    /// A UIKit-hosted `List` may retain its context-menu closure beyond a row
    /// redraw. Read the current list item when the action is tapped.
    private func beginRename(conversationID: String, fallback: ConversationRef) {
        let current = store.listViewModel.conversations.first(where: { $0.id == conversationID })
            ?? fallback
        renameTarget = current
        renameText = current.name ?? ""
    }

    private func archive(_ conversation: ConversationRef) {
        Task {
            do {
                _ = try await store.archiveConversation(conversation)
            }
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
    @Environment(\.colorScheme) private var colorScheme

    let conversation: ConversationListItem
    let activity: ConversationActivityState
    let queueReason: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(showsStatusIndicator ? activityColor : Color.clear)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 3) {
                
                Text(conversation.ref.name ?? conversation.id)
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
            if activity == .connecting {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            rowBackgroundColor,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "当前会话" : "打开会话")
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.13 : 0.09)
        }
        if activity.isActive {
            return Color.accentColor.opacity(0.045)
        }
        return .clear
    }

    private var detailText: String? {
        if let queueReason, !queueReason.isEmpty { return queueReason }
        if let worktree = conversation.ref.worktree { return worktree.branch }
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

    private var showsStatusIndicator: Bool {
        activity != .idle && activity != .succeeded && activity != .cancelled
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
                    Button(TalkifyLocalized.string("workspace.done")) { dismiss() }
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

private struct WorkspaceFileNavigationState: Equatable {
    var workspaceID: String?
    var directoryPath: String
    var directoryTitles: [String]
    var directoryPaths: [String]

    static func root(for workspace: Workspace?) -> Self {
        guard let workspace else {
            return .init(
                workspaceID: nil,
                directoryPath: "",
                directoryTitles: [],
                directoryPaths: []
            )
        }
        return .init(
            workspaceID: workspace.id,
            directoryPath: workspace.url.path,
            directoryTitles: [workspace.name],
            directoryPaths: [workspace.url.path]
        )
    }
}

private struct WorkspaceFilesView: View {
    let workspace: Workspace?
    let provider: WorkspaceFileContentProvider?
    @Binding var navigationState: WorkspaceFileNavigationState
    let refreshRevision: Int
    let isImporting: Bool
    let onSelectFile: (String) -> Void
    let onOpenBrowser: () -> Void
    let onStartConversation: () -> Void
    let onImportItems: () -> Void

    @State private var nodes: [WorkspaceFileListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if navigationState.directoryPaths.count > 1 {
                    Button { navigateBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.055), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(navigationState.directoryTitles.indices, id: \.self) { index in
                                if index > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                }
                                Button {
                                    navigate(to: index)
                                } label: {
                                    Text(navigationState.directoryTitles[index])
                                        .font(.caption.weight(index == navigationState.directoryTitles.count - 1 ? .semibold : .regular))
                                        .foregroundStyle(index == navigationState.directoryTitles.count - 1 ? .primary : .secondary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: navigationState.directoryTitles.count) { _, count in
                        guard count > 0 else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(count - 1, anchor: .trailing)
                        }
                    }
                }

                Button(action: onImportItems) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isImporting)
                .accessibilityLabel("导入文件")

                Button {
                    Task { await loadDirectory() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isLoading || isImporting)
                .accessibilityLabel("刷新文件")

                Button(action: onOpenBrowser) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("完整浏览")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                Divider().opacity(0.35)
            }

            if isLoading || isImporting {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                    if isImporting {
                        Text("正在复制到 \(workspace?.name ?? "工作区")…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            } else if let errorMessage {
                WorkspaceSectionEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "无法读取文件",
                    description: errorMessage,
                    primaryTitle: "重试",
                    primaryIcon: "arrow.clockwise",
                    primaryAction: { Task { await loadDirectory() } }
                )
            } else if nodes.isEmpty {
                ScrollView {
                    WorkspaceSectionEmptyState(
                        icon: "folder",
                        title: "工作区还是空的",
                        description: "让 CodeAgent 根据你的想法创建文件，或者从“文件”App 复制已有内容。",
                        primaryTitle: "让 CodeAgent 创建",
                        primaryIcon: "sparkles",
                        primaryAction: onStartConversation,
                        secondaryTitle: "导入文件",
                        secondaryIcon: "square.and.arrow.down",
                        secondaryAction: onImportItems
                    )
                }
                .scrollIndicators(.hidden, axes: .vertical)
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
            await initializeWorkspaceIfNeededAndRefresh()
        }
        .onChange(of: refreshRevision) { _, _ in
            Task { await loadDirectory() }
        }
    }

    private func navigateInto(_ node: WorkspaceFileListItem) {
        navigationState.directoryPath = node.path
        navigationState.directoryPaths.append(node.path)
        navigationState.directoryTitles.append(node.name)
        Task { await loadDirectory() }
    }

    private func navigateBack() {
        guard navigationState.directoryPaths.count > 1 else { return }
        navigationState.directoryPaths.removeLast()
        navigationState.directoryTitles.removeLast()
        navigationState.directoryPath = navigationState.directoryPaths.last
            ?? workspace?.url.path
            ?? ""
        Task { await loadDirectory() }
    }

    private func navigate(to index: Int) {
        guard navigationState.directoryPaths.indices.contains(index),
              index < navigationState.directoryPaths.count - 1 else { return }
        navigationState.directoryPaths = Array(navigationState.directoryPaths.prefix(index + 1))
        navigationState.directoryTitles = Array(navigationState.directoryTitles.prefix(index + 1))
        navigationState.directoryPath = navigationState.directoryPaths[index]
        Task { await loadDirectory() }
    }

    private func initializeWorkspaceIfNeededAndRefresh() async {
        guard let workspace else {
            navigationState = .root(for: nil)
            nodes = []
            return
        }

        // `.task` 会在 UIKit preview pop 后重新启动。只有 workspace 真正变化或
        // 尚未建立导航栈时才回到根目录；普通重现只刷新当前目录。
        if navigationState.workspaceID != workspace.id
            || navigationState.directoryPaths.isEmpty
            || navigationState.directoryPath.isEmpty {
            navigationState = .root(for: workspace)
        }
        await loadDirectory()
    }

    private func loadDirectory() async {
        guard let provider, !navigationState.directoryPath.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            nodes = try await provider.children(of: navigationState.directoryPath)
                .map(WorkspaceFileListItem.init)
        } catch {
            nodes = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct WorkspaceSectionEmptyState: View {
    let icon: String
    let title: String
    let description: String
    let primaryTitle: String
    let primaryIcon: String
    let primaryAction: () -> Void
    var secondaryTitle: String?
    var secondaryIcon: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 20)

            Image(systemName: icon)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 9) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: primaryIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)

                if let secondaryTitle, let secondaryIcon, let secondaryAction {
                    Button(action: secondaryAction) {
                        Label(secondaryTitle, systemImage: secondaryIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 280)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Section(TalkifyLocalized.string("workspace.tab.conversations")) {
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
                        Section(TalkifyLocalized.string("workspace.tab.files")) {
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

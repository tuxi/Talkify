//
//  WorkspaceView.swift
//  AgentKit
//
//  Created by xiaoyuan on 2026/6/25.
//

import SwiftUI
import AgentKit
import CoreKit
import FileViewerKit
import CryptoKit

/// 跨平台的三栏工作区外壳：
///
/// - **macOS**：自定义 `MacWorkspaceShell`，会话辅助栏与工具面板独立管理。
/// - **iPad (regular)**：`NavigationSplitView` 并排二栏，右侧 inspector 可收起。
/// - **iPhone (compact)**：`NavigationStack` — 侧栏为根视图，选中会话/新建草稿时 push 到详情，
///   inspector 自动变为 sheet。这是 iOS 聊天应用的标准导航模式。
///
/// 平台 Root 视图只需 `WorkspaceView(dependencies:)` 一行接入。
public struct WorkspaceView: View {
    
    private let dependencies: AgentDependencies
    
    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthManager.self) private var authManager
    @Environment(AgentManager.self) private var agentManager
    @Environment(UserManager.self) private var userManager
    
    @State private var router = AgentRouter()
    @State private var store: WorkspaceStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    @State private var showSettings = false
    @State private var settingsInitialSection: SettingsSection = .account
    @State private var showAccountPopover = false
    #if os(macOS)
    @State private var macLastConnectionDiagnostic: ComposerDiagnostic?
    @State private var macLastDiagnosticConnectionID: String?
    @State private var macFileSessions: [String: FileWorkspaceSession] = [:]
    @State private var macReviewSessions: [String: FileReviewSession] = [:]
    #endif
    
#if os(iOS)
    // MARK: iOS-specific state (SharedImport / DeepLink / AuthState)
    
    @State private var sharedImportRequest: SharedImportInbox.Request?
    @State private var workspaceContext: IOSWorkspaceContext?
    @State private var showWorkspaceBrowser = false
    @State private var workspaceBrowserInitialPath: String?
    @State private var filePreviewPath: String?
    @State private var exportArchiveURL: URL?
    
    @State private var searchText = ""
    
    private var fileProvider: WorkspaceFileContentProvider {
        WorkspaceFileContentProvider(store: store)
    }
#endif
    
    /// 跨平台 FileContentProvider：iOS 提供 WorkspaceFileContentProvider，macOS 暂无。
    private var fileProviderForInspector: (any AgentKit.FileContentProvider)? {
#if os(iOS)
        return fileProvider
#else
        return nil
#endif
    }
    
    /// Inspector 工作台。iOS 启用内部 NavigationStack，macOS 暂时使用平铺详情，
    /// 避免与 NavigationSplitView inspector 列的导航状态冲突。
    @ViewBuilder
    private var inspectorContent: some View {
#if os(iOS)
        TalkifyInspectorWorkbench(
            selection: store.inspectorSelection,
            fileProvider: fileProviderForInspector,
            usesNavigationStack: true,
            workspaceState: store.inspectorWorkspaceState,
            workspaceRoot: store.selectedConversation.map {
                URL(fileURLWithPath: $0.workspacePath, isDirectory: true)
            }
        )
        .environment(\.workflowStore, store.workflowStore)
        .environment(\.runtimeClient, store.client)
#else
        TalkifyInspectorWorkbench(
            selection: store.inspectorSelection,
            fileProvider: nil,
            usesNavigationStack: false,
            workspaceState: store.inspectorWorkspaceState,
            workspaceRoot: store.selectedConversation.map {
                URL(fileURLWithPath: $0.workspacePath, isDirectory: true)
            }
        )
            .environment(\.workflowStore, store.workflowStore)
            .environment(\.runtimeClient, store.client)
#endif
    }
    
    public init(dependencies: AgentDependencies) {
        self.dependencies = dependencies
        self._store = State(initialValue: AppContainer.makeWorkspaceStore(dependencies: dependencies))
    }
    
    
    private func flushMacFileDrafts() {
#if os(macOS)
        for session in macFileSessions.values {
            if let document = session.document { Task { _ = await document.flush() } }
        }
#endif
    }

    public var body: some View {
        content
            .task {
#if os(iOS)
                store.startLifecycleNetworkMonitor()
#endif
#if os(iOS) || os(macOS)
                await container.ensureAgentRuntimeStarted()
#endif
                await store.handleAppBecameActive()
            }
            .onChange(of: scenePhase) { _, newValue in
                switch newValue {
                case .active:
                    Task {
                        #if os(iOS)
                        await container.ensureAgentRuntimeStarted()
                        #endif
                        await store.handleAppBecameActive()
                    }
                case .background:
                    flushMacFileDrafts()
                    store.handleAppEnteredBackground()
                case .inactive:
                    flushMacFileDrafts()
                @unknown default:
                    break
                }
            }
            .onDisappear {
                flushMacFileDrafts()
                store.handleWorkspaceDisappeared()
            }
            .onChange(of: container.conversationNotifications.pendingConversation, initial: true) { _, identity in
                guard let identity else { return }
                Task { await openNotificationConversation(identity) }
            }
    }
    
    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macLayout
        #else
        if horizontalSizeClass == .compact {
            #if os(iOS)
            ChatDrawerWorkspace(dependencies: container.makeAgentDependencies())
            #else
            iOSCompactLayout
            #endif
        } else {
            standardLayout
        }
        #endif
    }
    
    #if os(macOS)
    private var macPageID: String {
        switch store.selectItem {
        case .conversationDetail(let conversation): "conversation:\(conversation.id)"
        case .draft: "draft:\(store.draftNavigationRevision)"
        case .automation: "automation"
        case .workflow: "workflow"
        }
    }

    private var macIsConversation: Bool {
        if case .conversationDetail = store.selectItem { return true }
        return false
    }

    private var macSupportsInspector: Bool {
        switch store.selectItem {
        case .conversationDetail, .draft: true
        case .automation, .workflow: false
        }
    }

    private var macTitle: String {
        switch store.selectItem {
        case .conversationDetail: store.activeConversationViewModel?.conversation?.name ?? "对话"
        case .draft: "新对话"
        case .automation: "自动化"
        case .workflow: "工作流"
        }
    }

    private var macConnectionDiagnostic: ComposerDiagnostic? {
        guard let connection = container.runtimeServers.activeConnection,
              let monitor = try? container.runtimeServers.externalStatusMonitor(connectionID: connection.id) else { return nil }
        if let issue = ComposerDiagnostic.runtime(monitor.diagnosticSnapshot, name: connection.displayName) { return issue }
        // A periodic probe changes offline → checking → offline. Keep the last
        // failure until a successful check, so the banner does not flash/reopen.
        if [.starting, .checking, .reconnecting].contains(monitor.status),
           macLastDiagnosticConnectionID == connection.id {
            return macLastConnectionDiagnostic
        }
        return nil
    }

    private var macComposerDiagnostic: ComposerDiagnostic? {
        if let issue = macConnectionDiagnostic { return issue }
        guard let connection = container.runtimeServers.activeConnection,
              let context = container.runtimeServers.activeContext,
              context.serverConnectionID == connection.id,
              !context.modelCatalog.connections.contains(where: { $0.models.contains(where: \.available) }) else { return nil }
        let missingCredentials = context.modelCatalog.connections.contains { $0.credential?.status == "missing" }
        return ComposerDiagnostic(
            id: "models:\(connection.id):\(context.modelCatalog.revision)",
            title: missingCredentials ? "模型凭据尚未配置" : "当前没有可用模型",
            message: "请打开模型设置，检查提供商、凭据与可用模型。",
            details: "环境：\(connection.displayName)\n模型目录版本：\(context.modelCatalog.revision)\n提供商数量：\(context.modelCatalog.connections.count)\n可用模型：0",
            destination: .models
        )
    }

    private var macLayout: some View {
        ZStack {
            MacWorkspaceShell(
                title: macTitle,
                pageID: macPageID,
                isConversation: macIsConversation,
                supportsInspector: macSupportsInspector,
                allowsFinderReveal: container.runtimeServers.activeConnection?.kind == .local,
                fileWorkspace: macCurrentFileSession,
                reviewWorkspace: macCurrentReviewSession
            ) {
                VStack(spacing: 0) {
                    SidebarView(showSettings: $showSettings)
                    Divider()
                    footer
                }
            } content: {
                NavigationStack(path: $router.path) {
                    Group {
                        switch store.selectItem {
                        case .conversationDetail(let conversation):
                            ConversationDetailView(conversation: conversation)
                                .withAgentNavigationDestinations(router: router, dependencies: dependencies)
                        case .draft:
                            ConversationDetailView(conversation: nil)
                        case .automation:
                            AutomationDashboardView()
                        case .workflow:
                            WorkflowDashboardView()
                        }
                    }
                    .navigationTitle("")
                }
            } inspector: { panel in
                macInspectorPanel(panel)
            }
            .withAgentSheetDestinations(sheetDestinations: $router.presentedSheet, dependencies: dependencies)
            .withAgentCoverDestinations(coverDestinations: $router.presentedCover, dependencies: dependencies)
            .environment(router)
            .environment(store)
            .environment(\.composerEnvironmentName, container.runtimeServers.activeConnection?.displayName ?? "执行环境")
            .environment(\.composerEnvironmentSymbol, container.runtimeServers.activeConnection?.kind == .remote ? "network" : "desktopcomputer")
            .environment(\.composerDiagnostic, macComposerDiagnostic)
            .onChange(of: macConnectionDiagnostic, initial: true) { _, issue in
                macLastDiagnosticConnectionID = container.runtimeServers.activeConnectionID
                macLastConnectionDiagnostic = issue
            }
            .environment(\.composerRecheckEnvironment, {
                let connectionID = container.runtimeServers.activeConnectionID
                await container.ensureAgentRuntimeStarted()
                guard container.runtimeServers.activeConnectionID == connectionID else { return }
                let healthy = (try? await container.runtimeServers.checkExternal(connectionID: connectionID)) == true
                guard healthy, container.runtimeServers.activeConnectionID == connectionID else { return }
                await container.refreshActiveRuntimeContext()
            })
            .environment(\.composerOpenModelSettings, {
                settingsInitialSection = .providers
                showSettings = true
            })
            .environment(\.conversationUsesWorkspaceHeader, true)
            .environment(\.sessionRailOpenSettings, { destination in
                settingsInitialSection = destination == .skills ? .customize : .servers
                showSettings = true
            })
            .environment(\.conversationUsesSessionRail, store.sessionRail.hasTaskSurface(for: store.selectedConversation?.id))
            .task(id: macFileSessionKey) {
                store.workspaceFileNavigationContext = macFileSessionKey
                store.workspaceFileNavigationEnabled = true
                store.workspaceReviewNavigationEnabled = true
                prepareMacFileSession()
                prepareMacReviewSession()
            }
            .task(id: "\(macFileSessionKey)|\(store.inspectorWorkspaceState.fileOpenRequest?.id.uuidString ?? "")") {
                await openMacFileRequest()
            }
            .task(id: "\(macFileSessionKey)|review|\(store.inspectorWorkspaceState.reviewOpenRequest?.id.uuidString ?? "")") {
                await openMacReviewRequest()
            }
            .onChange(of: macFileSessionKey) { oldKey, _ in
                if let previous = macFileSessions[oldKey]?.document { Task { _ = await previous.flush() } }
            }
            .ignoresSafeArea(.container, edges: .top)

            if showSettings {
                SettingsView(initialSection: settingsInitialSection, sessionID: store.selectedConversation?.id) {
                    showSettings = false
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    @ViewBuilder
    private func macInspectorPanel(_ panel: MacWorkspaceLayout.Panel) -> some View {
        switch panel {
        case .sessionRail:
            SessionRailView()
        case .detail:
            InspectorNavigationView(
                initialSelection: store.inspectorSelection,
                fileProvider: nil,
                pathState: store.inspectorWorkspaceState.selectionPathState,
                usesNavigationStack: false
            )
            .environment(\.workflowStore, store.workflowStore)
            .environment(\.runtimeClient, store.client)
        case .files, .changes:
            if macInspectorRoot != nil,
               store.inspectorWorkspaceState.tabs.contains(where: {
                   $0.entry == (panel == .files ? .files : .review)
               }) {
                if panel == .files {
                    if let session = macCurrentFileSession {
                        TalkifyInspectorFileWorkspace(session: session)
                            .id(session.id)
                    } else if !macFilesAreLocal {
                        WorkspaceStatusView("当前运行环境不提供文件浏览与编辑", symbol: "folder.badge.questionmark", message: "文件需要由所属 Runtime 读取，不能使用本机同名路径。")
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                } else {
                    if let session = macCurrentReviewSession {
                        TalkifyInspectorReviewWorkspace(session: session).id(session.id)
                    } else if !macFilesAreLocal {
                        WorkspaceStatusView("当前运行环境尚未提供 Changes 审阅", symbol: "network", message: "远程仓库的变更需要由所属 Runtime 读取。")
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
            } else {
                MacInspectorStatusView(.needsProject)
            }
        case .terminal, .browser:
            MacInspectorStatusView(.unavailable(title: panel.title, symbol: panel.symbol))
        }
    }

    private func openMacFileRequest() async {
        let state = store.inspectorWorkspaceState
        guard let request = state.fileOpenRequest else { return }
        let key = macFileSessionKey
        defer {
            if state.fileOpenRequest?.id == request.id { state.fileOpenRequest = nil }
        }
        prepareMacFileSession()
        guard request.contextID == key, let session = macCurrentFileSession else { return }
        await session.openLocation(request.path, line: request.line, isDirectory: request.isDirectory)
    }

    private func openMacReviewRequest() async {
        let state = store.inspectorWorkspaceState
        guard let request = state.reviewOpenRequest else { return }
        defer { if state.reviewOpenRequest?.id == request.id { state.reviewOpenRequest = nil } }
        prepareMacReviewSession()
        guard request.contextID == macFileSessionKey, let session = macCurrentReviewSession else { return }
        await session.refresh()
        guard !Task.isCancelled, state.reviewOpenRequest?.id == request.id else { return }
        if let path = request.path { session.reveal(path) }
    }

    private var macFileSessionKey: String {
        String(describing: container.runtimeServers.activeConnectionID) + "|" + macPageID + "|" + (macInspectorRoot?.path ?? "")
    }
    private var macFilesAreLocal: Bool {
        guard let kind = container.runtimeServers.activeConnection?.kind else { return true }
        return kind == .local || kind == .embedded
    }
    private var macCurrentFileSession: FileWorkspaceSession? { macFileSessions[macFileSessionKey] }
    private func prepareMacFileSession() {
        guard macFilesAreLocal, let root = macInspectorRoot, macFileSessions[macFileSessionKey] == nil else { return }
        if macFileSessions.count >= 12 {
            let removable = macFileSessions.keys.filter { $0 != macFileSessionKey && macFileSessions[$0]?.hasUnsavedChanges == false }
            for key in removable.prefix(max(1, macFileSessions.count - 10)) { macFileSessions[key] = nil }
        }
        let provider = LocalFileContentProvider(rootURL: root, showsHiddenFiles: true)
        let git = GitWorkingTreeReviewProvider(rootURL: root)
        macFileSessions[macFileSessionKey] = FileWorkspaceSession(rootPath: root.path, provider: provider, statusLoader: { try await git.workingTreeStatuses() })
    }

    private var macReviewSessionKey: String {
        String(describing: container.runtimeServers.activeConnectionID) + "|" + (macInspectorRoot?.resolvingSymlinksInPath().path ?? "")
    }
    private var macCurrentReviewSession: FileReviewSession? { macReviewSessions[macReviewSessionKey] }
    private func prepareMacReviewSession() {
        guard macFilesAreLocal, let root = macInspectorRoot, macCurrentReviewSession == nil else { return }
        if macReviewSessions.count >= 12 {
            for key in macReviewSessions.keys.filter({ $0 != macReviewSessionKey }).prefix(2) { macReviewSessions[key] = nil }
        }
        let identity = String(describing: container.runtimeServers.activeConnectionID) + "|" + root.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        macReviewSessions[macReviewSessionKey] = FileReviewSession(provider: GitWorkingTreeReviewProvider(rootURL: root), persistenceKey: "talkify.changes.viewed." + digest)
    }

    private var macInspectorRoot: URL? {
        if macIsConversation, let conversation = store.selectedConversation {
            return URL(fileURLWithPath: conversation.workspacePath, isDirectory: true)
        }
        return store.draft?.workspace?.url
    }
    #endif

    // MARK: - iPhone (compact) — NavigationStack
    
    @ViewBuilder
    private var iOSCompactLayout: some View {
        NavigationStack(path: $router.path) {
            SidebarView(showSettings: $showSettings)
                .navigationDestination(for: AgentNavigationDestination.self) { destination in
                    Group {
                        switch destination {
                        case .conversationDetail(let conversation):
                            ConversationDetailView(conversation: conversation)
                        case .draft:
                            ConversationDetailView(conversation: nil)
                        case .automation:
                            AutomationDashboardView()
                        case .workflow:
                            WorkflowDashboardView()
                        }
                    }
                    .inspector(isPresented: $store.isInspectorPresented) {
                        inspectorContent
                    }
                }
        }
        .withAgentSheetDestinations(sheetDestinations: $router.presentedSheet, dependencies: dependencies)
        .withAgentCoverDestinations(coverDestinations: $router.presentedCover, dependencies: dependencies)
        .onChange(of: store.selectedConversation) { _, newValue in
            guard let ref = newValue else { return }
            // 选中会话 → push 到详情
            pushToDetailIfNeeded(.conversationDetail(conversation: ref))
        }
        .onChange(of: store.draftNavigationRevision) { _, _ in
            if store.draft != nil {
                // 新建草稿 → push 到详情
                pushToDetailIfNeeded(.draft)
            }
        }
        .onChange(of: router.path) { _, newPath in
            // 用户返回侧栏时清除选中态，确保再次点同一行仍可触发 push
            if newPath.isEmpty {
                store.selectItem = .draft
            }
        }
        .environment(router)
        .environment(store)
    }
    
    /// 仅在当前 path 为空时 push（避免重复压栈）。
    private func pushToDetailIfNeeded(_ destination: AgentNavigationDestination) {
        guard router.path.isEmpty else { return }
        router.navigate(to: destination)
    }
    
    private func openNotificationConversation(
        _ identity: RuntimeConversationIdentity
    ) async {
        guard identity.serverConnectionID == container.runtimeServers.activeConnectionID else {
            try? await container.activateRuntimeServer(
                connectionID: identity.serverConnectionID
            )
            return
        }
        let sessionID = identity.conversationID
        if !store.listViewModel.conversations.contains(where: { $0.id == sessionID }) {
            await store.listViewModel.refresh()
        }
        store.selectConversation(sessionID: sessionID)
        guard let conversation = store.selectedConversation, conversation.id == sessionID else { return }
        
        if horizontalSizeClass == .compact {
            router.path = [.conversationDetail(conversation: conversation)]
        }
        container.conversationNotifications.consumePendingConversation(identity)
    }
    
    // MARK: - iPad / macOS (regular) — NavigationSplitView
    
    @ViewBuilder
    private var standardLayout: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
#if os(iOS)
                workspaceHubSidebar
                    .platformSidebarColumnWidth()
                    .task {
                        if workspaceContext == nil {
                            workspaceContext = IOSWorkspaceContext(store: store)
                        }
                    }
#else
                VStack {
                    SidebarView(showSettings: $showSettings)
                    Divider()
                    footer
                }
                .platformSidebarColumnWidth()
#endif
            } detail: {
                NavigationStack(path: $router.path) {
                    switch store.selectItem {
                    case .conversationDetail(let conversation):
                        ConversationDetailView(conversation: conversation)
                            .withAgentNavigationDestinations(router: router, dependencies: dependencies)
    #if os(iOS) // iPad 上关闭sidebar 后增加显示侧栏的按钮
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    if columnVisibility == .detailOnly {
                                        Button {
                                            columnVisibility = .all
                                        } label: {
                                            Image(systemName: "sidebar.left")
                                                .accessibilityLabel(TalkifyLocalized.string("workspace.show_sidebar"))
                                        }
                                    }
                                }
                            }
    #endif
    #if os(macOS)
                            .frame(minWidth: 80, idealWidth: 280, maxWidth: 650)
    #endif
                            .navigationTitle(store.activeConversationViewModel?.conversation?.name ?? "")
                    case .draft:
                        ConversationDetailView(conversation: nil)
                            .frame(minWidth: 80, idealWidth: 280, maxWidth: 650)
                    case .automation:
                        AutomationDashboardView()
                            .frame(minWidth: 80, idealWidth: 280, maxWidth: 650)
                            .navigationTitle("自动化")
                    case .workflow:
                        WorkflowDashboardView()
                            .frame(minWidth: 80, idealWidth: 280, maxWidth: 650)
                            .navigationTitle("工作流")
                    }
                }
                .inspector(isPresented: $store.isInspectorPresented) {
                    inspectorContent
                        .platformInspectorColumnWidth()
                }
            }
#if os(iOS)
            // MARK: iOS Sheets
            .sheet(item: $sharedImportRequest) { request in
                SharedImportConfirmationView(
                    request: request,
                    onCreate: { workspaceName in
                        let claim = try SharedImportInbox.claim(request)
                        let sourceURL = try SharedImportInbox.workspaceSourceURL(for: claim)
                        store.beginDraft()
                        try await store.importAndSelectProject(from: sourceURL, named: workspaceName)
                        SharedImportInbox.complete(claim)
                    },
                    onFinished: { result in
                        sharedImportRequest = nil
                        if case .created = result {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                checkSharedImportInbox()
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showWorkspaceBrowser) {
                workspaceBrowserSheetContent
            }
            .sheet(isPresented: Binding(
                get: { filePreviewPath != nil },
                set: { if !$0 { filePreviewPath = nil } }
            )) {
                if let path = filePreviewPath {
                    FilePreviewHost(
                        filePath: path,
                        fileName: (path as NSString).lastPathComponent,
                        provider: fileProvider,
                        showDiff: false
                    )
                }
            }
            .sheet(item: Binding(
                get: { exportArchiveURL.map { IdentifiableURL(url: $0) } },
                set: { exportArchiveURL = $0?.url }
            )) { wrapper in
                ShareSheet(items: [wrapper.url]) {
                    try? FileManager.default.removeItem(at: wrapper.url.deletingLastPathComponent())
                }
            }
            // MARK: iOS Observers
            .task { checkSharedImportInbox() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                checkSharedImportInbox()
            }
            .onChange(of: container.pendingDeepLinkWorkspacePath) { _, path in
                guard let path else { return }
                container.pendingDeepLinkWorkspacePath = nil
                let resolved = path.resolvingCurrentSandboxPath
                let items = fileProvider.buildWorkspaceItems()
                workspaceBrowserInitialPath = items.first(where: { $0.rootPath == resolved })?.rootPath ?? resolved
                showWorkspaceBrowser = true
            }
#endif
            .onChange(of: store.selectedConversation, { oldValue, newValue in
                //                store.isInspectorPresented = false
            })
            .withAgentSheetDestinations(sheetDestinations: $router.presentedSheet, dependencies: dependencies)
            .withAgentCoverDestinations(coverDestinations: $router.presentedCover, dependencies: dependencies)
            .environment(router)
            .environment(store)
            
            if showSettings {
                SettingsView(
                    initialSection: settingsInitialSection,
                    sessionID: store.selectedConversation?.id
                ) {
                    showSettings = false
                }
                #if os(macOS)
                .background(Color(nsColor: .windowBackgroundColor)) // 不透明，挡住下层
                #endif
            }
        }
#if os(macOS)
        .toolbar(showSettings ? .hidden : .automatic, for: .windowToolbar) // 打开设置时隐藏窗口 chrome
#endif
    }
    
#if os(iOS)
    // MARK: - iOS Helpers
    
    private func checkSharedImportInbox() {
        guard sharedImportRequest == nil,
              presentedSheetCount == 0
        else { return }
        sharedImportRequest = SharedImportInbox.pendingRequests().first
    }
    
    /// Tracks whether any of our iOS sheets is currently presented.
    private var presentedSheetCount: Int {
        (sharedImportRequest != nil ? 1 : 0) +
        (showWorkspaceBrowser ? 1 : 0) +
        (filePreviewPath != nil ? 1 : 0) +
        (exportArchiveURL != nil ? 1 : 0)
    }
    
    @ViewBuilder
    private var workspaceHubSidebar: some View {
        if let workspaceContext {
            ZStack(alignment: .bottom) {
                WorkspaceHubView(
                    selectedConversation: .init(get: {
                        store.selectedConversation
                    }, set: { ref in
                        if let ref {
                            store.selectItem = .conversationDetail(conversation: ref)
                        } else {
                            store.selectItem = .draft
                        }
                    }),
                    searchText: searchText,
                    fileProvider: fileProvider,
                    workspaceContext: workspaceContext,
                    isBottomHide: true,
                    onWorkspaceBrowserRequested: { showWorkspaceBrowser = true },
                    onNewChat: {
                        columnVisibility = .detailOnly
                        store.beginDraft()
                    },
                    onSettings: { openSettings($0) },
                    onFileSelected: { filePreviewPath = $0 },
                    onWorkspaceExportReady: { exportArchiveURL = $0 }
                )
                VStack {
                    if store.selectedConversation != nil {
                        // iPad 中，当已经选择一个对话时，显示新建对话
                        Button {
                            columnVisibility = .detailOnly
                            store.beginDraft()
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
                        .padding(.horizontal)
                        
                    }
                    Divider()
                    footer
                }
            }
        } else {
            Color.clear
        }
    }
    
    
    @ViewBuilder
    private var workspaceBrowserSheetContent: some View {
        let items = fileProvider.buildWorkspaceItems()
        let initial = workspaceBrowserInitialPath.flatMap { path in
            items.first(where: { $0.rootPath == path })
        }
        WorkspaceBrowserView(
            workspaces: items,
            fileProvider: fileProvider,
            initialWorkspace: initial,
            onSelectWorkspace: { item in
                store.beginDraft()
                store.selectWorkspace(Workspace(url: URL(fileURLWithPath: item.rootPath)))
                showWorkspaceBrowser = false
                workspaceBrowserInitialPath = nil
            },
            onSelectFile: { path in
                showWorkspaceBrowser = false
                workspaceBrowserInitialPath = nil
                filePreviewPath = path
            },
            onViewConversations: { _ in
                showWorkspaceBrowser = false
                workspaceBrowserInitialPath = nil
                columnVisibility = .all
            }
        )
    }
#endif
    
}

extension WorkspaceView {
    /// 平台适配的账户菜单入口：
    /// - macOS：`AppMenu`（NSPopover），跟随触发视图锚定。
    /// - iOS (iPad)：`Button` + SwiftUI `.popover`。
    @ViewBuilder
    private var footer: some View {
        #if os(macOS)
        HStack(spacing: 8) {
            ActiveRuntimeServerIndicator(style: .chip) {
                openSettings(.servers)
            }
            macFooterIdentity
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        #else
        CodingTasksButton()
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        if !authManager.isRegistered {
            Button {
                openSettings()
            } label: {
                Label(TalkifyLocalized.string("workspace.settings"), systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        } else {
            Button {
                showAccountPopover = true
            } label: {
                accountLabel
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .accessibilityLabel("\(TalkifyLocalized.string("workspace.account"))：\(accountName)")
            .popover(isPresented: $showAccountPopover) {
                AccountMenuContent(
                    accountName: accountName,
                    accountInitial: accountInitial,
                    usage: agentManager.usage,
                    isRedeemingResetCard: agentManager.isRedeemingResetCard,
                    usageError: agentManager.usageError,
                    onContentSizeChange: { _ in },
                    onRefreshUsage: { agentManager.fetchUsage() },
                    onRefreshCards: { agentManager.refreshResetCards() },
                    onRedeemResetCard: { agentManager.redeemResetCard($0) },
                    onSettings: {
                        openSettings()
                        showAccountPopover = false
                    },
                    onLogout: {
                        Task { await container.disconnectGateway() }
                    }
                )
            }
            .task { await loadAccountDataIfNeeded() }
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var macFooterIdentity: some View {
        if !authManager.isRegistered {
            Button {
                openSettings()
            } label: {
                Label(TalkifyLocalized.string("workspace.settings"), systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 30)
        } else {
            AppMenu(
                presentation: .fixedToTrigger(preferredEdge: .maxY)
            ) { resizeMenu in
                AccountMenuContent(
                    accountName: accountName,
                    accountInitial: accountInitial,
                    usage: agentManager.usage,
                    isRedeemingResetCard: agentManager.isRedeemingResetCard,
                    usageError: agentManager.usageError,
                    onContentSizeChange: resizeMenu,
                    onRefreshUsage: { agentManager.fetchUsage() },
                    onRefreshCards: { agentManager.refreshResetCards() },
                    onRedeemResetCard: { agentManager.redeemResetCard($0) },
                    onSettings: { openSettings() },
                    onLogout: {
                        Task { await container.disconnectGateway() }
                    }
                )
            } label: {
                accountLabel
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(TalkifyLocalized.string("workspace.account"))：\(accountName)")
            .task { await loadAccountDataIfNeeded() }
        }
    }
    #endif

    private func openSettings(_ section: SettingsSection = .account) {
        settingsInitialSection = section
        showSettings = true
    }
    
    /// 登录后加载账户资料与用量。
    private func loadAccountDataIfNeeded() async {
        guard authManager.isRegistered else { return }
        await userManager.refreshProfileIfNeeded()
        agentManager.fetchUsage()
    }
    
    /// 公共账户标签：头像首字母 + 昵称。
    private var accountLabel: some View {
        HStack(spacing: 10) {
            Text(accountInitial)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())

            Text(accountName)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    private var accountName: String {
        guard authManager.isRegistered else { return TalkifyLocalized.string("workspace.not_logged_in") }

        let candidates = [
            userManager.profile?.nickname,
            authManager.displayNickname
        ]
        if let name = candidates.lazy.compactMap({ value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }).first {
            return name
        }

        if let username = userManager.profile?.username.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty,
           !username.allSatisfy(\.isNumber) {
            return username
        }
        if let userID = authManager.token?.userId {
            return String(format: TalkifyLocalized.string("workspace.user_label"), "\(userID)")
        }
        return TalkifyLocalized.string("workspace.account")
    }

    private var accountInitial: String {
        String(accountName.prefix(1)).uppercased()
    }

    private var usageTitle: String {
        guard let usage = agentManager.usage else { return TalkifyLocalized.string("workspace.remaining_usage") }
        let remaining = max(usage.weekly.unitsLimit - usage.weekly.unitsUsed, 0)
        return "\(TalkifyLocalized.string("workspace.remaining_usage"))：\(formattedUnits(remaining)) / \(formattedUnits(usage.weekly.unitsLimit))"
    }

    private func formattedUnits(_ value: Int) -> String {
        value >= 1_000_000
            ? String(format: "%.1fM", Double(value) / 1_000_000)
            : (value >= 1_000 ? String(format: "%.1fK", Double(value) / 1_000) : "\(value)")
    }
}

// MARK: - Platform-Adaptive Column Widths

private extension View {
    /// 跨平台的侧栏列宽：macOS 用 min/max 范围，iOS 用固定值。
    @ViewBuilder
    func platformSidebarColumnWidth() -> some View {
#if os(iOS)
        //        self.navigationSplitViewColumnWidth(320) // iPhone
        self.navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 320) // iPad
#else
        self.navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 339)
#endif
    }
    
    /// 跨平台的 inspector 列宽：macOS 用 min/max 范围，iOS 用固定值。
    @ViewBuilder
    func platformInspectorColumnWidth() -> some View {
#if os(iOS)
        self.inspectorColumnWidth(320)
#else
        self.inspectorColumnWidth(min: 150, ideal: 238, max: 800)
#endif
    }
}

#if os(iOS)
// MARK: - Sheet Helpers (iOS)

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let completion: () -> Void
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completion() }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

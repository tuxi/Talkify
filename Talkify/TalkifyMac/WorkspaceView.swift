//
//  WorkspaceView.swift
//  AgentKit
//
//  Created by xiaoyuan on 2026/6/25.
//

import SwiftUI
import AgentKit
import CoreKit
#if os(iOS)
import FileViewerKit
#endif

/// 跨平台的三栏工作区外壳：
///
/// - **macOS / iPad (regular)**：`NavigationSplitView` 并排二栏，右侧 inspector 可收起。
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
    @State private var showAccountPopover = false
    
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
    
    /// Inspector 内容视图。iOS 用 NavigationStack 容器，macOS 用平铺切换。
    /// macOS 上的 NavigationStack 会与 NavigationSplitView 的 inspector 列导航状态冲突，
    /// 导致 `comparisonTypeMismatch` 崩溃，暂时回退到 InspectorView。
    @ViewBuilder
    private var inspectorContent: some View {
#if os(iOS)
        InspectorNavigationView(
            initialSelection: store.inspectorSelection,
            fileProvider: fileProviderForInspector
        )
        .environment(\.workflowStore, store.workflowStore)
        .environment(\.runtimeClient, store.client)
#else
        InspectorView(selection: store.inspectorSelection)
            .environment(\.workflowStore, store.workflowStore)
            .environment(\.runtimeClient, store.client)
#endif
    }
    
    public init(dependencies: AgentDependencies) {
        self.dependencies = dependencies
        self._store = State(initialValue: AppContainer.makeWorkspaceStore(dependencies: dependencies))
    }
    
    
    public var body: some View {
        content
            .task {
#if os(iOS)
                store.startLifecycleNetworkMonitor()
                await container.ensureAgentRuntimeStarted()
#endif
                await store.handleAppBecameActive()
            }
            .onChange(of: scenePhase) { _, newValue in
                switch newValue {
                case .active:
                    Task { await store.handleAppBecameActive() }
                case .background:
                    store.handleAppEnteredBackground()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onDisappear {
                store.handleWorkspaceDisappeared()
            }
            .onChange(of: container.conversationNotifications.pendingSessionID, initial: true) { _, sessionID in
                guard let sessionID else { return }
                Task { await openNotificationSession(sessionID) }
            }
    }
    
    @ViewBuilder
    private var content: some View {
        if horizontalSizeClass == .compact {
//            iOSCompactLayout
            ChatDrawerWorkspace(dependencies: container.makeAgentDependencies())
        } else {
            standardLayout
        }
    }
    
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
                store.selectedConversation = nil
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
    
    private func openNotificationSession(_ sessionID: String) async {
        if !store.listViewModel.conversations.contains(where: { $0.id == sessionID }) {
            await store.listViewModel.refresh()
        }
        store.selectConversation(sessionID: sessionID)
        guard let conversation = store.selectedConversation, conversation.id == sessionID else { return }
        
        if horizontalSizeClass == .compact {
            router.path = [.conversationDetail(conversation: conversation)]
        }
        container.conversationNotifications.consumePendingSessionID(sessionID)
    }
    
    // MARK: - iPad / macOS (regular) — NavigationSplitView
    
    @ViewBuilder
    private var standardLayout: some View {
        if showSettings {
            SettingsView {
                showSettings = false
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
#if os(iOS)
                workspaceHubSidebar
                    .platformSidebarColumnWidth()
                    .task {
                        if workspaceContext == nil {
                            workspaceContext = IOSWorkspaceContext(store: store)
                        }
                    }
                    .navigationTitle("Code")
#if os(iOS)
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer,
                        prompt: "搜索会话…"
                    )
                    .navigationBarTitleDisplayMode(.large)
#endif
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
                    ConversationDetailView(conversation: store.selectedConversation)
                        .withAgentNavigationDestinations(router: router, dependencies: dependencies)
#if os(iOS) // iPad 上关闭sidebar 后增加显示侧栏的按钮
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                if columnVisibility == .detailOnly {
                                    Button {
                                        columnVisibility = .all
                                    } label: {
                                        Image(systemName: "sidebar.left")
                                            .accessibilityLabel("显示侧栏")
                                    }
                                }
                            }
                        }
#endif
#if os(macOS)
                        .frame(maxWidth: 800)
                        .frame(minWidth: 230)
#endif
                        .navigationTitle(store.activeConversationViewModel?.conversation?.name ?? "")
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
            .onChange(of: container.authManager.isLoggedIn) { _, loggedIn in
                if !loggedIn {
                    sharedImportRequest = nil
                    showWorkspaceBrowser = false
                    filePreviewPath = nil
                }
            }
#endif
            .withAgentSheetDestinations(sheetDestinations: $router.presentedSheet, dependencies: dependencies)
            .withAgentCoverDestinations(coverDestinations: $router.presentedCover, dependencies: dependencies)
            .environment(router)
            .environment(store)
        }
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
                    selectedConversation: $store.selectedConversation,
                    searchText: "",
                    fileProvider: fileProvider,
                    workspaceContext: workspaceContext,
                    onWorkspaceBrowserRequested: { showWorkspaceBrowser = true },
                    onNewChat: {
                        columnVisibility = .detailOnly
                        store.beginDraft()
                    },
                    onSettings: { showSettings = true },
                    onFileSelected: { filePreviewPath = $0 },
                    onWorkspaceExportReady: { exportArchiveURL = $0 }
                )
                VStack {
                    if store.selectedConversation != nil {
                        // iPad 中，当已经选择一个对话时，显示新建对话
                        Button {
    //                        onNewChat?()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "square.and.pencil")
                                Text(store.draft == nil ? "新对话" : "继续草稿")
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
    private var footer: some View {
        #if os(macOS)
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
                onSettings: { showSettings = true },
                onLogout: { authManager.logout() }
            )
        } label: {
            accountLabel
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityLabel("账户：\(accountName)")
        .task { await loadAccountDataIfNeeded() }
        #else
        Button {
            showAccountPopover = true
        } label: {
            accountLabel
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityLabel("账户：\(accountName)")
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
                    showSettings = true
                    showAccountPopover = false
                },
                onLogout: { authManager.logout() }
            )
        }
        .task { await loadAccountDataIfNeeded() }
        #endif
    }
    
    /// 登录后加载账户资料与用量。
    private func loadAccountDataIfNeeded() async {
        guard authManager.isLoggedIn, authManager.isRegistered else { return }
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
        guard authManager.isLoggedIn else { return "未登录" }

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
            return "用户 \(userID)"
        }
        return "账户"
    }

    private var accountInitial: String {
        String(accountName.prefix(1)).uppercased()
    }

    private var usageTitle: String {
        guard let usage = agentManager.usage else { return "剩余用量" }
        let remaining = max(usage.weekly.unitsLimit - usage.weekly.unitsUsed, 0)
        return "剩余用量：\(formattedUnits(remaining)) / \(formattedUnits(usage.weekly.unitsLimit))"
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
        self.navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 330) // iPad
#else
        self.navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
#endif
    }
    
    /// 跨平台的 inspector 列宽：macOS 用 min/max 范围，iOS 用固定值。
    @ViewBuilder
    func platformInspectorColumnWidth() -> some View {
#if os(iOS)
        self.inspectorColumnWidth(320)
#else
        self.inspectorColumnWidth(min: 280, ideal: 320, max: 480)
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

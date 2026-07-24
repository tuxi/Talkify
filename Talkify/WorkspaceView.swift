//
//  WorkspaceView.swift
//  AgentKit
//
//  Created by xiaoyuan on 2026/6/25.
//

import SwiftUI
import AgentKit

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

    @State private var router = AgentRouter()
    @State private var store: WorkspaceStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    @State private var showSettings = false

    #if os(iOS)
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
            iOSCompactLayout
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
                SidebarView(showSettings: $showSettings)
                    .platformSidebarColumnWidth()
            } detail: {
                NavigationStack(path: $router.path) {
                    ConversationDetailView(conversation: store.selectedConversation)
                        .withAgentNavigationDestinations(router: router, dependencies: dependencies)
                }
                .inspector(isPresented: $store.isInspectorPresented) {
                    inspectorContent
                        .platformInspectorColumnWidth()
                }
            }
            .withAgentSheetDestinations(sheetDestinations: $router.presentedSheet, dependencies: dependencies)
            .withAgentCoverDestinations(coverDestinations: $router.presentedCover, dependencies: dependencies)
            .environment(router)
            .environment(store)
        }
    }
}

// MARK: - Platform-Adaptive Column Widths

private extension View {
    /// 跨平台的侧栏列宽：macOS 用 min/max 范围，iOS 用固定值。
    @ViewBuilder
    func platformSidebarColumnWidth() -> some View {
        #if os(iOS)
        self.navigationSplitViewColumnWidth(320)
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

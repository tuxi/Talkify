//
//  TalkifyRootView.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/6/24.
//

#if os(iOS)

import SwiftUI
import AgentKit
import CoreKit
import FeatureAuth

// MARK: - ChatDrawerWorkspace

/// SwiftUI shell that owns the `WorkspaceStore` lifecycle and bridges to the
/// UIKit drawer container (`ChatRootViewController`).
///
/// The store is created synchronously in `init` via `State(initialValue:)` —
/// identical to `WorkspaceView`'s pattern — so the drawer is never waiting on
/// an async task before it can render.
///
/// Replicates the lifecycle logic that `WorkspaceView` provides for the
/// standard `NavigationSplitView` / `NavigationStack` layouts, but targets
/// the custom drawer architecture exclusively on iOS.
struct ChatDrawerWorkspace: View {

    let dependencies: AgentDependencies

    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: WorkspaceStore

    // MARK: - Init

    init(dependencies: AgentDependencies) {
        self.dependencies = dependencies
        self._store = State(initialValue: AppContainer.makeWorkspaceStore(dependencies: dependencies))
    }

    // MARK: - Body

    var body: some View {
        ChatRootViewRepresentable(store: store, dependencies: dependencies, container: container)
            .ignoresSafeArea()
            .task {
                store.startLifecycleNetworkMonitor()
                await container.ensureAgentRuntimeStarted()
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
                Task {
                    if !store.listViewModel.conversations.contains(where: { $0.id == sessionID }) {
                        await store.listViewModel.refresh()
                    }
                    store.selectConversation(sessionID: sessionID)
                    container.conversationNotifications.consumePendingSessionID(sessionID)
                }
            }
    }

}

// MARK: - UIViewControllerRepresentable

private struct ChatRootViewRepresentable: UIViewControllerRepresentable {

    let store: WorkspaceStore
    let dependencies: AgentDependencies
    let container: AppContainer

    func makeUIViewController(context: Context) -> UINavigationController {
        let root = ChatRootViewController(store: store, container: container, dependencies: dependencies)
        let nav = UINavigationController(rootViewController: root)
        nav.setNavigationBarHidden(true, animated: false)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

// MARK: - TalkifyRootView

/// iOS 平台根视图：按设备类型分流 iPad 与 iPhone。
///
/// - **iPad**：始终使用 `WorkspaceView`，内部根据 `horizontalSizeClass`
///   自动切换三栏 `NavigationSplitView` ↔ `NavigationStack`。
///   iPad 在 Slide Over / 分屏时可能为 compact，但始终应走 WorkspaceView。
/// - **iPhone**：使用 `ChatDrawerWorkspace`，以 UIKit 驱动的
///   抽屉式架构（ChatGPT 风格滑出侧栏）。
struct TalkifyRootView: View {

    @Environment(AppContainer.self) private var container
    @AppStorage("provider.onboarding.completed.v1")
    private var hasCompletedProviderOnboarding = false

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        Group {
            if isPad {
                WorkspaceView(dependencies: container.makeAgentDependencies())
            } else {
                ChatDrawerWorkspace(dependencies: container.makeAgentDependencies())
            }
        }
        .sheet(isPresented: providerOnboardingBinding) {
            ProviderOnboardingView(
                hasCompletedOnboarding: $hasCompletedProviderOnboarding
            )
        }
    }

    private var providerOnboardingBinding: Binding<Bool> {
        Binding(
            get: {
                !hasCompletedProviderOnboarding
                    && !container.providerConnections.hasAvailableModels
                    && !container.authManager.showLoginSheet
            },
            set: { presented in
                if !presented { hasCompletedProviderOnboarding = true }
            }
        )
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { container.authManager.showLoginSheet },
            set: { container.authManager.showLoginSheet = $0 }
        )
    }
}

#endif

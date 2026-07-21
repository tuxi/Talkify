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
private struct ChatDrawerWorkspace: View {

    let dependencies: AgentDependencies

    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: WorkspaceStore

    // MARK: - Init

    init(dependencies: AgentDependencies) {
        self.dependencies = dependencies
        self._store = State(initialValue: Self.makeStore(dependencies: dependencies))
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

    // MARK: - Factory

    private static func makeStore(dependencies: AgentDependencies) -> WorkspaceStore {
        WorkspaceStore(
            client: dependencies.client,
            toolRegistry: dependencies.toolRegistry,
            timelineExtensions: dependencies.timelineExtensions,
            conversationRendererMode: dependencies.conversationRendererMode,
            onAuthExpired: dependencies.onAuthExpired,
            localStateStore: dependencies.localStateStore,
            userAssetPicker: dependencies.userAssetPicker,
            userAssetUploader: dependencies.userAssetUploader,
            userAssetPreviewResolver: dependencies.userAssetPreviewResolver,
            attentionReadStore: dependencies.attentionReadStore,
            onAttentionEvent: dependencies.onAttentionEvent
        )
    }
}

// MARK: - UIViewControllerRepresentable

private struct ChatRootViewRepresentable: UIViewControllerRepresentable {

    let store: WorkspaceStore
    let dependencies: AgentDependencies
    let container: AppContainer

    func makeUIViewController(context: Context) -> ChatRootViewController {
        ChatRootViewController(store: store, container: container, dependencies: dependencies)
    }

    func updateUIViewController(_ uiViewController: ChatRootViewController, context: Context) {}
}

// MARK: - TalkifyRootView

struct TalkifyRootView: View {

    @Environment(AppContainer.self) private var container

    var body: some View {
        if container.authManager.isLoggedIn {
            ChatDrawerWorkspace(dependencies: container.makeAgentDependencies())
        } else {
            AuthView(viewModel: container.makeAuthViewModel())
        }
    }
}

#endif

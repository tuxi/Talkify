//
//  ChatViewController.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/19.
//

#if os(iOS)
import SwiftUI
import UIKit
import AgentKit

/// Wraps `ConversationDetailView` with a `NavigationStack` so internal navigations
/// (e.g. inspector sheets, tool approval panels) still function inside the drawer
/// detail pane.
private struct ChatDetailWrapper: View {
    let store: WorkspaceStore
    let dependencies: AgentDependencies
    let onMenuTapped: () -> Void
    /// AgentKit 的 FileContentProvider，用于 InspectorNavigationView
    let fileProvider: (any AgentKit.FileContentProvider)?
    let onInspectorFilesRequested: () -> Void

    @State private var router = AgentRouter()
    @State private var showInspector = false

    var body: some View {
        NavigationStack(path: $router.path) {
            ConversationDetailView(conversation: store.selectedConversation)
                .withAgentNavigationDestinations(router: router, dependencies: dependencies)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onMenuTapped()
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16))
                                .clipShape(Circle())
                        }
                    }

                }
        }
        .sheet(isPresented: $showInspector) {
            TalkifyInspectorWorkbench(
                selection: store.inspectorSelection,
                fileProvider: fileProvider,
                usesNavigationStack: true,
                onOpenFiles: onInspectorFilesRequested
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(store)
            .environment(\.workflowStore, store.workflowStore)
            .environment(\.runtimeClient, store.client)
        }
        .withAgentSheetDestinations(sheetDestinations: $router.presentedSheet, dependencies: dependencies)
        .withAgentCoverDestinations(coverDestinations: $router.presentedCover, dependencies: dependencies)
        .onChange(of: showInspector) { _, presented in
            store.isInspectorPresented = presented
        }
        .onChange(of: store.isInspectorPresented) { _, presented in
            if showInspector != presented { showInspector = presented }
        }
        .environment(router)
        .environment(store)
    }
}

/// The right-hand detail pane in the drawer layout.
///
/// Hosts `ConversationDetailView` (SwiftUI) via `UIHostingController` and overlays
/// a UIKit menu button that triggers drawer open. Conversation selection is driven
/// by the shared `WorkspaceStore` — no manual `load(_:)` needed.
final class ChatViewController: UIViewController {

    var onMenuTap: (() -> Void)?
    var onMaskTap: (() -> Void)?
    /// AgentKit 的 FileContentProvider，注入到 ChatDetailWrapper 用于 InspectorNavigationView
    var fileProvider: (any AgentKit.FileContentProvider)?
    var onInspectorFilesRequested: (() -> Void)?

    private let store: WorkspaceStore
    private let dependencies: AgentDependencies
    private var hostingController: UIHostingController<ChatDetailWrapper>?

    /// Semi-transparent overlay that dims the chat area when the drawer is open.
    /// Tap gesture is on the mask itself — when `alpha == 0` the gesture is
    /// automatically ignored, so ChatView content remains interactive.
    lazy var maskView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.alpha = 0.0
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTapMaskGes))
        view.addGestureRecognizer(tap)
        return view
    }()

    // MARK: - Init

    init(store: WorkspaceStore, dependencies: AgentDependencies) {
        self.store = store
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)

        embedDetailView()

        // Mask sits above SwiftUI content but below the menu button.
        view.addSubview(maskView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        hostingController?.view.frame = view.bounds
        maskView.frame = view.bounds
    }

    // MARK: - Embed

    private func embedDetailView() {
        let detailView = ChatDetailWrapper(
            store: store,
            dependencies: dependencies,
            onMenuTapped: { [weak self] in self?.onMenuTap?() },
            fileProvider: fileProvider,
            onInspectorFilesRequested: { [weak self] in
                self?.onInspectorFilesRequested?()
            }
        )
        let host = UIHostingController(rootView: detailView)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        hostingController = host
    }


    @objc func onTapMaskGes(_ tap: UITapGestureRecognizer) {
        onMaskTap?()
    }
}

#endif

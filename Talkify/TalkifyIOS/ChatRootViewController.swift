//
//  ChatRootViewController.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/19.
//

#if os(iOS)
import UIKit
import AgentKit
import Observation
import SwiftUI
import CoreKit
import FileViewerKit

/// Root container that implements the ChatGPT-style drawer layout.
///
/// - `WorkspaceHubViewController` is the persistent left drawer.
/// - `ChatViewController` is the right detail pane that slides to reveal the drawer.
///
/// Uses **frame-based** animation (not `CGAffineTransform`) because `UIHostingController`
/// subviews use Auto Layout internally, and setting `frame` on a view with an active
/// transform produces undefined behaviour.
///
/// Conversation selection is driven by a shared `WorkspaceStore` — when the user
/// taps a conversation in the drawer the store updates, `ConversationDetailView`
/// reacts automatically, and the drawer closes.
final class ChatRootViewController: UIViewController {

    private let store: WorkspaceStore
    private let dependencies: AgentDependencies
    private let workspaceContext: IOSWorkspaceContext

    private let drawerVC: WorkspaceHubViewController
    private let chatVC: ChatViewController

    private let drawerWidth: CGFloat = 320
    private let maxMaskAlpha: CGFloat = 0.3
    private var isDrawerOpen = false
    
    private let container: AppContainer

    /// 桥接层：将 WorkspaceStore 数据适配到 FileViewerKit 和 AgentKit 的协议。
    private lazy var fileProvider = WorkspaceFileContentProvider(
        store: store,
        workspaceContext: workspaceContext
    )

    /// Invisible view that sits below `chatVC.view` and carries its shadow.
    /// Separated because `chatVC.view` uses `masksToBounds` for corner clipping,
    /// which would also clip the shadow.
    private let chatShadowView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: -8, height: 0)
        view.layer.shadowRadius = 24
        view.layer.shadowOpacity = 0
        view.layer.masksToBounds = false
        return view
    }()

    private lazy var panGesture = UIPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
    )

    /// Pan on the exposed drawer area to close it by swiping left.
    private lazy var drawerPanGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrawerPan(_:)))
        gesture.delegate = self
        return gesture
    }()

    // MARK: - Init

    init(store: WorkspaceStore, container: AppContainer, dependencies: AgentDependencies) {
        self.store = store
        self.container = container
        self.dependencies = dependencies
        self.workspaceContext = IOSWorkspaceContext(store: store)
        self.drawerVC = WorkspaceHubViewController(
            store: store,
            workspaceContext: workspaceContext
        )
        self.chatVC = ChatViewController(store: store, dependencies: dependencies)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        // 必须在 addChild / access view 之前注入 provider，
        // 否则 WorkspaceHubViewController.viewDidLoad 中创建的
        // WorkspaceHubView 会拿到 nil 的 fileProvider。
        drawerVC.fileProvider = fileProvider
        chatVC.fileProvider = fileProvider

        // Drawer (behind, stationary)
        addChild(drawerVC)
        view.addSubview(drawerVC.view)
        drawerVC.didMove(toParent: self)
        drawerVC.view.addGestureRecognizer(drawerPanGesture)

        // Shadow layer — sits between drawer and chat, mirrors chat's frame.
        view.addSubview(chatShadowView)

        // Chat detail (above, slides right)
        addChild(chatVC)
        view.addSubview(chatVC.view)
        chatVC.didMove(toParent: self)

        chatVC.view.layer.cornerRadius = 36
        chatVC.view.layer.masksToBounds = true
        chatVC.view.addGestureRecognizer(panGesture)
        
        drawerVC.onSelectedConversation = { [weak self] in
            self?.setDrawer(open: false, animated: true)
        }

        drawerVC.onSettingsTap = { [weak self] in
            self?.handleSettingsTap()
        }

        drawerVC.onWorkspaceBrowserRequested = { [weak self] in
            self?.showWorkspaceBrowser(initialWorkspace: self?.currentWorkspaceItem())
        }

        drawerVC.onFileSelected = { [weak self] path in
            self?.showFilePreview(path: path)
        }

        chatVC.onMenuTap = { [weak self] in
            self?.setDrawer(open: self?.isDrawerOpen == false, animated: true)
        }
        
        chatVC.onMaskTap = { [weak self] in
            if self?.isDrawerOpen == true {
                self?.setDrawer(open: false, animated: true)
            }
        }

        // Auto-close drawer when a conversation is selected via the store.
//        beginObservingSelection()
        
        observeAuthState()
        observeDeepLink()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: true)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        drawerVC.view.frame = CGRect(x: 0, y: 0, width: drawerWidth, height: view.bounds.size.height)
        applyChatFrame(animated: false)
    }

    // MARK: - Frame Management

    /// Computes the target frame for the chat view given the drawer state.
    private func chatFrame(open: Bool) -> CGRect {
        if open {
            return view.bounds.offsetBy(dx: drawerWidth, dy: 0)
        } else {
            return view.bounds
        }
    }

    /// Applies the chat view's frame, optionally with spring animation.
    ///
    /// When `animated` is `false` this is safe to call from `viewDidLayoutSubviews`
    /// — it just snaps to the correct position without disturbing an in-flight
    /// animation (the animation system continues to use its presentation layer).
    private func applyChatFrame(animated: Bool) {
        let targetFrame = chatFrame(open: isDrawerOpen)
        let cornerRadius: CGFloat = isDrawerOpen ? 36 : 0
        let maskAlpha: CGFloat = isDrawerOpen ? maxMaskAlpha : 0
        let shadowOpacity: Float = isDrawerOpen ? 0.35 : 0

        let changes = {
            self.chatVC.view.frame = targetFrame
            self.chatVC.view.layer.cornerRadius = cornerRadius
            self.chatVC.maskView.alpha = maskAlpha

            self.chatShadowView.frame = targetFrame
            self.chatShadowView.layer.cornerRadius = cornerRadius
            self.chatShadowView.layer.shadowOpacity = shadowOpacity
        }

        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0.6,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
        
        let feedback = UISelectionFeedbackGenerator()
        feedback.selectionChanged()
    }

    // MARK: - Drawer Toggle

    private func setDrawer(open: Bool, animated: Bool) {
        guard isDrawerOpen != open else { return }
        isDrawerOpen = open

        // Dismiss keyboard before sliding, so it doesn't linger over the drawer.
        chatVC.view.endEditing(true)

        applyChatFrame(animated: animated)
    }

    // MARK: - Pan-Time Updates

    /// Called during pan gestures to update the chat view position, corner radius,
    /// mask alpha, and shadow without animation (real-time tracking).
    private func updateChatToOffset(_ offset: CGFloat) {
        let progress = offset / drawerWidth
        let offsetFrame = view.bounds.offsetBy(dx: offset, dy: 0)

        chatVC.view.frame = offsetFrame
        chatVC.view.layer.cornerRadius = progress * 36
        chatVC.maskView.alpha = progress * maxMaskAlpha

        chatShadowView.frame = offsetFrame
        chatShadowView.layer.cornerRadius = progress * 36
        chatShadowView.layer.shadowOpacity = Float(progress * 0.35)
    }

    // MARK: - Chat Pan Gesture (on chatVC.view)

    /// Handles swipe-left / swipe-right on the chat detail view.
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translationX = gesture.translation(in: view).x
        let currentOffset = isDrawerOpen ? drawerWidth : 0
        let nextOffset = min(max(currentOffset + translationX, 0), drawerWidth)

        switch gesture.state {
        case .began:
            chatVC.view.endEditing(true)

        case .changed:
            updateChatToOffset(nextOffset)

        case .ended, .cancelled:
            let velocityX = gesture.velocity(in: view).x
            isDrawerOpen = nextOffset > drawerWidth * 0.45 || velocityX > 600
            applyChatFrame(animated: true)
            gesture.setTranslation(.zero, in: view)

        default:
            break
        }
    }

    // MARK: - Drawer Pan Gesture (on drawerVC.view)

    /// Handles swipe-left on the exposed drawer area to close it.
    @objc private func handleDrawerPan(_ gesture: UIPanGestureRecognizer) {
        let translationX = gesture.translation(in: view).x
        // When drawer is open the chat offset starts at drawerWidth; dragging left
        // (negative translationX) decreases the offset to close the drawer.
        let nextOffset = min(max(drawerWidth + translationX, 0), drawerWidth)

        switch gesture.state {
        case .began:
            chatVC.view.endEditing(true)

        case .changed:
            updateChatToOffset(nextOffset)

        case .ended, .cancelled:
            let velocityX = gesture.velocity(in: view).x
            // Close if dragged more than 55 % of the way or flicked left fast enough.
            isDrawerOpen = nextOffset > drawerWidth * 0.55 && velocityX > -300
            applyChatFrame(animated: true)
            gesture.setTranslation(.zero, in: view)

        default:
            break
        }
    }
    
    private func handleSettingsTap() {
        let settingsView = SettingsView { [weak self] in
            self?.dismiss(animated: true)
        }
            .environment(container.authManager)
            .environment(container.agentManager)
            .environment(container.userManager)
        let settingsVC = UIHostingController(rootView: settingsView)
        self.present(settingsVC, animated: true)
    }

    // MARK: - Workspace Browser

    /// Resolves the current workspace to a `WorkspaceItem` for use as `initialWorkspace`.
    private func currentWorkspaceItem() -> FileViewerKit.WorkspaceItem? {
        guard let root = workspaceContext.activeWorkspace?.url.path else { return nil }
        return fileProvider.buildWorkspaceItems().first(where: { $0.rootPath == root })
    }

    /// Presents the full-screen workspace browser (FileViewerKit).
    /// Pass `initialWorkspace` to skip the list and go directly to workspace detail.
    private func showWorkspaceBrowser(initialWorkspace: FileViewerKit.WorkspaceItem? = nil) {
        let browserView = FileViewerKit.WorkspaceBrowserView(
            workspaces: fileProvider.buildWorkspaceItems(),
            fileProvider: fileProvider,
            initialWorkspace: initialWorkspace,
            onSelectWorkspace: { [weak self] item in
                // 选择工作区 → 关闭浏览器 + 切换工作区上下文
                self?.dismiss(animated: true) {
                    guard let self else { return }
                    self.workspaceContext.activate(
                        .init(url: URL(fileURLWithPath: item.rootPath)),
                        in: self.store
                    )
                }
            },
            onSelectFile: { [weak self] filePath in
                self?.dismiss(animated: true) {
                    self?.showFilePreview(path: filePath)
                }
            },
            onViewConversations: { [weak self] workspaceID in
                self?.dismiss(animated: true) {
                    guard let self else { return }
                    self.workspaceContext.activate(
                        .init(url: URL(fileURLWithPath: workspaceID)),
                        in: self.store
                    )
                    self.setDrawer(open: true, animated: true)
                }
            }
        )

        let browserVC = UIHostingController(rootView: browserView)
        browserVC.modalPresentationStyle = .fullScreen
        self.present(browserVC, animated: true)
    }

    // MARK: - File Preview

    /// Pushes file preview with UIKit slide animation. The pushed VC carries its own
    /// NavigationStack for the back button, so UINavigationController's bar stays hidden.
    private func showFilePreview(path: String) {
        let previewWithNav = NavigationStack {
            FilePreviewHost(
                filePath: path,
                fileName: (path as NSString).lastPathComponent,
                provider: fileProvider,
                showDiff: false
            )
        }

        let previewVC = UIHostingController(rootView: previewWithNav)
        navigationController?.pushViewController(previewVC, animated: true)
    }

    // MARK: - Observation
    
    private func observeAuthState() {
        withObservationTracking {
            _ = container.authManager.isLoggedIn // 建立追踪
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.presentedViewController != nil {
                    self.dismiss(animated: true)
                }
                self.observeAuthState() // 必须重新注册观察，这是一次性的
            }
        }

    }

    private func observeDeepLink() {
        withObservationTracking {
            _ = container.pendingDeepLinkWorkspacePath
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self, let path = self.container.pendingDeepLinkWorkspacePath else { return }
                self.container.pendingDeepLinkWorkspacePath = nil
                let item = self.fileProvider.buildWorkspaceItems().first(where: {
                    let current = $0.rootPath.resolvingCurrentSandboxPath
                    return current == path
                })
                self.showWorkspaceBrowser(initialWorkspace: item)
                self.observeDeepLink()
            }
        }
    }

    /// Watches `store.selectedConversation` changes and auto-closes the drawer
    /// when the user picks a conversation.
//    private func beginObservingSelection() {
//        withObservationTracking {
//            _ = store.selectedConversation
//        } onChange: { [weak self] in
//            DispatchQueue.main.async {
//                self?.setDrawer(open: false, animated: true)
//                self?.beginObservingSelection()
//            }
//        }
//    }
}

// MARK: - UIGestureRecognizerDelegate

extension ChatRootViewController: UIGestureRecognizerDelegate {

    /// Only claim the drawer pan when the drawer is open AND the swipe is
    /// primarily horizontal (moving left to close). Vertical swipes pass
    /// through to the drawer's native scroll view.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isDrawerOpen,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return false
        }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) && velocity.x < 0
    }
}

#endif

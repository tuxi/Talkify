//
//  WorkspaceHubViewController.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

#if os(iOS)
import UIKit
import SwiftUI
import AgentKit
import FileViewerKit

/// 工作区枢纽视图控制器 — 抽屉面板的内容。
///
/// 替代原有的 `DrawerViewController`，内部从单一 `ConversationListView` 升级为
/// 多 Tab 的 `WorkspaceHubView`：
/// - [💬 会话] → 当前项目的扁平会话列表
/// - [📄 文件] → 当前工作目录的文件浏览
/// - [🔍 搜索] → 当前项目内的会话与文件搜索
///
/// WorkspaceHeader 的主区域切换项目，右侧按钮进入当前项目的完整浏览器。
final class WorkspaceHubViewController: UIViewController {

    var store: WorkspaceStore
    let workspaceContext: IOSWorkspaceContext
    var searchText: String = ""
    var fileProvider: WorkspaceFileContentProvider?

    var onSelectedConversation: (() -> Void)?
    var onSettingsTap: (() -> Void)?
    var onWorkspaceBrowserRequested: (() -> Void)?
    var onFileSelected: ((String) -> Void)?

    // MARK: - Init

    init(store: WorkspaceStore, workspaceContext: IOSWorkspaceContext) {
        self.store = store
        self.workspaceContext = workspaceContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let hubView = WorkspaceHubView(
            selectedConversation: .init(
                get: { [weak self] in self?.store.selectedConversation },
                set: { [weak self] in
                    guard let self else { return }
                    self.store.selectedConversation = $0
                    self.workspaceContext.synchronize(with: $0, in: self.store)
                    self.onSelectedConversation?()
                }
            ),
            searchText: searchText,
            fileProvider: fileProvider,
            workspaceContext: workspaceContext,
            onWorkspaceBrowserRequested: { [weak self] in
                self?.onWorkspaceBrowserRequested?()
            },
            onNewChat: { [weak self] in
                guard let self else { return }
                if let workspace = self.workspaceContext.activeWorkspace {
                    self.workspaceContext.activate(workspace, in: self.store)
                } else {
                    self.store.beginDraft()
                }
                self.onSelectedConversation?()
            },
            onSettings: { [weak self] in
                self?.onSettingsTap?()
            },
            onFileSelected: { [weak self] path in
                self?.onFileSelected?(path)
            }
        )
        .environment(store)

        let rootController = UIHostingController(rootView: AnyView(hubView))
        rootController.view.backgroundColor = .clear

        addChild(rootController)
        rootController.didMove(toParent: self)

        view.addSubview(rootController.view)
        rootController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rootController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootController.view.topAnchor.constraint(equalTo: view.topAnchor),
            rootController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
#endif

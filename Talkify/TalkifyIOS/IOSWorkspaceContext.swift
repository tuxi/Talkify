//
//  IOSWorkspaceContext.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/22.
//

#if os(iOS)
import Foundation
import Observation
import AgentKit

/// iOS 抽屉的一等工作区上下文。
///
/// AgentKit 的 `selectWorkspace` 描述的是「草稿绑定到哪个目录」，而 iOS Hub
/// 还需要一个独立、稳定的浏览上下文。这个类型由宿主持有，使会话、文件和搜索
/// 始终围绕同一个项目工作，同时不改变 macOS 侧栏的交互模型。
@MainActor
@Observable
final class IOSWorkspaceContext {
    struct Selection: Identifiable, Hashable {
        let serverConnectionID: String
        let groupingID: String
        let displayName: String
        let workspace: Workspace?
        let isServerDerived: Bool

        var id: String {
            "\(serverConnectionID)::\(groupingID)"
        }
    }

    let serverConnectionID: String
    let serverKind: RuntimeServerKind
    private(set) var activeSelection: Selection?

    init(
        store: WorkspaceStore,
        serverConnectionID: String = RuntimeServerConnection.embeddedID,
        serverKind: RuntimeServerKind = .embedded
    ) {
        self.serverConnectionID = serverConnectionID
        self.serverKind = serverKind
        self.activeSelection = Self.initialSelection(
            in: store,
            serverConnectionID: serverConnectionID,
            serverKind: serverKind
        )
    }

    var isExternalServer: Bool {
        serverKind != .embedded
    }

    var activeWorkspace: Workspace? {
        activeSelection?.workspace
    }

    var activeGroupingID: String? {
        activeSelection?.groupingID
    }

    var activeDisplayName: String? {
        activeSelection?.displayName
    }

    func availableSelections(in store: WorkspaceStore) -> [Selection] {
        var result: [Selection] = []
        var seenGroupingIDs: Set<String> = []

        if !isExternalServer {
            for workspace in store.recentWorkspaces.workspaces + store.projects.projects {
                let selection = Self.selection(
                    for: workspace,
                    serverConnectionID: serverConnectionID
                )
                guard seenGroupingIDs.insert(selection.groupingID).inserted else { continue }
                result.append(selection)
            }
        }

        let conversations = store.listViewModel.conversations
            + store.listViewModel.archivedConversations
        for conversation in conversations {
            let selection = Self.selection(
                for: conversation,
                serverConnectionID: serverConnectionID
            )
            guard seenGroupingIDs.insert(selection.groupingID).inserted else { continue }
            result.append(selection)
        }
        return result
    }

    func conversations(in store: WorkspaceStore, includeArchived: Bool = false) -> [ConversationRef] {
        guard let activeGroupingID else { return [] }
        let source = includeArchived
            ? store.listViewModel.conversations + store.listViewModel.archivedConversations
            : store.listViewModel.conversations
        return source.filter { $0.workspaceGroupingID == activeGroupingID }
    }

    /// 切换内嵌项目会建立本地草稿；External Server 只切换浏览分组，
    /// 避免浏览远端目录时提前改变会话状态。
    func activate(_ selection: Selection, in store: WorkspaceStore) {
        activeSelection = selection
        if isExternalServer {
            if let selectedConversation = store.selectedConversation,
               selectedConversation.workspaceGroupingID != selection.groupingID {
                store.selectedConversation = nil
            }
            return
        }
        guard let workspace = selection.workspace else {
            store.selectedConversation = conversations(in: store).first
            return
        }
        store.beginDraft()
        store.selectWorkspace(workspace)
    }

    func activate(_ workspace: Workspace, in store: WorkspaceStore) {
        let selection = availableSelections(in: store).first {
            $0.workspace?.id == workspace.id
        } ?? Self.selection(
            for: workspace,
            serverConnectionID: serverConnectionID
        )
        activate(selection, in: store)
    }

    /// 只有用户明确点击“新对话”时才为当前服务器工作区创建草稿。
    /// 浏览 External 工作区本身不应污染草稿或 iPhone 本地项目状态。
    func beginDraft(in store: WorkspaceStore) {
        store.beginDraft()
        guard let workspace = activeWorkspace else { return }
        store.selectWorkspace(workspace)
    }

    /// 从外部或搜索结果打开会话时，让 Hub 跟随会话所属的基础项目。
    func synchronize(with conversation: ConversationRef?, in store: WorkspaceStore) {
        guard let conversation else {
            if let draftWorkspace = store.draft?.workspace {
                activeSelection = Self.selection(
                    for: draftWorkspace,
                    serverConnectionID: serverConnectionID
                )
            }
            return
        }

        if let matching = availableSelections(in: store).first(where: {
            $0.groupingID == conversation.workspaceGroupingID
        }) {
            activeSelection = matching
            return
        }

        activeSelection = Self.selection(
            for: conversation,
            serverConnectionID: serverConnectionID
        )
    }

    /// 会话列表由 Runtime 异步加载。External Server 的 Mac 路径不会进入
    /// iPhone 的本地 recent/projects，因此列表刷新后要从 ConversationRef
    /// 建立展示投影，不能等待用户先选择一个本地目录。
    func reconcile(in store: WorkspaceStore) {
        let selections = availableSelections(in: store)
        if let activeSelection,
           let current = selections.first(where: { $0.id == activeSelection.id }) {
            self.activeSelection = current
            return
        }
        if let selectedConversation = store.selectedConversation {
            synchronize(with: selectedConversation, in: store)
            return
        }
        activeSelection = selections.first
    }

    func contains(_ conversation: ConversationRef) -> Bool {
        guard let activeGroupingID else { return false }
        return conversation.workspaceGroupingID == activeGroupingID
    }

    private static func initialSelection(
        in store: WorkspaceStore,
        serverConnectionID: String,
        serverKind: RuntimeServerKind
    ) -> Selection? {
        if let draftWorkspace = store.draft?.workspace {
            return selection(
                for: draftWorkspace,
                serverConnectionID: serverConnectionID
            )
        }
        if let conversation = store.selectedConversation {
            return selection(
                for: conversation,
                serverConnectionID: serverConnectionID
            )
        }
        if serverKind != .embedded {
            return store.listViewModel.conversations.first.map {
                selection(
                    for: $0,
                    serverConnectionID: serverConnectionID
                )
            }
        }
        return (store.recentWorkspaces.workspaces.first ?? store.projects.projects.first)
            .map {
                selection(
                    for: $0,
                    serverConnectionID: serverConnectionID
                )
            }
    }

    private static func selection(
        for workspace: Workspace,
        serverConnectionID: String
    ) -> Selection {
        Selection(
            serverConnectionID: serverConnectionID,
            groupingID: "path:\(workspace.url.canonicalPathForGrouping)",
            displayName: workspace.name,
            workspace: workspace,
            isServerDerived: false
        )
    }

    private static func selection(
        for conversation: ConversationRef,
        serverConnectionID: String
    ) -> Selection {
        let path = conversationBaseWorkspacePath(conversation)
        return Selection(
            serverConnectionID: serverConnectionID,
            groupingID: conversation.workspaceGroupingID,
            displayName: conversation.workspaceGroupingName,
            workspace: path.map {
                Workspace(url: URL(fileURLWithPath: $0, isDirectory: true))
            },
            isServerDerived: true
        )
    }

    private static func conversationBaseWorkspacePath(
        _ conversation: ConversationRef
    ) -> String? {
        if let baseWorkspaceID = conversation.baseWorkspaceID,
           baseWorkspaceID.hasPrefix("/") {
            return baseWorkspaceID
        }
        if let rootPath = conversation.workspace?.localRootPath,
           !rootPath.isEmpty {
            return rootPath
        }
        if let inferredBaseWorkspacePath = conversation.inferredBaseWorkspacePath {
            return inferredBaseWorkspacePath
        }
        guard !conversation.workspacePath.isEmpty else { return nil }
        return conversation.workspacePath
    }
}
#endif

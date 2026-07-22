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
    private(set) var activeWorkspace: Workspace?

    init(store: WorkspaceStore) {
        activeWorkspace = Self.initialWorkspace(in: store)
    }

    var activeGroupingID: String? {
        activeWorkspace.map(Self.groupingID(for:))
    }

    func availableWorkspaces(in store: WorkspaceStore) -> [Workspace] {
        var result: [Workspace] = []
        var seenGroupingIDs: Set<String> = []

        for workspace in store.recentWorkspaces.workspaces + store.projects.projects {
            let groupingID = Self.groupingID(for: workspace)
            guard seenGroupingIDs.insert(groupingID).inserted else { continue }
            result.append(workspace)
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

    /// 切换项目会建立该项目的本地草稿，使右侧内容和抽屉上下文同步。
    /// 不会创建 Runtime 会话；首条消息发送时仍沿用 AgentKit 的延迟创建语义。
    func activate(_ workspace: Workspace, in store: WorkspaceStore) {
        activeWorkspace = workspace
        store.beginDraft()
        store.selectWorkspace(workspace)
    }

    /// 从外部或搜索结果打开会话时，让 Hub 跟随会话所属的基础项目。
    func synchronize(with conversation: ConversationRef?, in store: WorkspaceStore) {
        guard let conversation else {
            if let draftWorkspace = store.draft?.workspace {
                activeWorkspace = draftWorkspace
            }
            return
        }

        if let matching = availableWorkspaces(in: store).first(where: {
            Self.groupingID(for: $0) == conversation.workspaceGroupingID
        }) {
            activeWorkspace = matching
            return
        }

        let path = conversation.inferredBaseWorkspacePath ?? conversation.workspacePath
        guard !path.isEmpty else { return }
        activeWorkspace = Workspace(url: URL(fileURLWithPath: path))
    }

    func contains(_ conversation: ConversationRef) -> Bool {
        guard let activeGroupingID else { return false }
        return conversation.workspaceGroupingID == activeGroupingID
    }

    private static func initialWorkspace(in store: WorkspaceStore) -> Workspace? {
        if let draftWorkspace = store.draft?.workspace {
            return draftWorkspace
        }
        if let conversation = store.selectedConversation {
            let candidates = store.recentWorkspaces.workspaces + store.projects.projects
            if let matching = candidates.first(where: {
                groupingID(for: $0) == conversation.workspaceGroupingID
            }) {
                return matching
            }
            let path = conversation.inferredBaseWorkspacePath ?? conversation.workspacePath
            if !path.isEmpty {
                return Workspace(url: URL(fileURLWithPath: path))
            }
        }
        return store.recentWorkspaces.workspaces.first ?? store.projects.projects.first
    }

    private static func groupingID(for workspace: Workspace) -> String {
        "path:\(workspace.url.canonicalPathForGrouping)"
    }
}
#endif

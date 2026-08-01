//
//  TalkifyInspectorWorkbench.swift
//  Talkify
//
//  Created by Codex on 2026/8/1.
//

import SwiftUI
import AgentKit
import FileViewerKit

/// Talkify 对 AgentKit Inspector 工作台的宿主协调层。
///
/// AgentKit 负责入口、selection 和内部导航；Talkify 为文件标签注入实时工作区，
/// 并逐步接入终端、浏览器、审阅和侧边聊天的长生命周期资源。
struct TalkifyInspectorWorkbench: View {
    let selection: InspectorSelection?
    let fileProvider: (any AgentKit.FileContentProvider)?
    let usesNavigationStack: Bool
    let workspaceState: InspectorWorkspaceState
    let workspaceRoot: URL?

    var body: some View {
        InspectorWorkbenchView(
            selection: selection,
            fileProvider: fileProvider,
            usesNavigationStack: usesNavigationStack,
            workspaceState: workspaceState,
            onOpenEntry: { _ in },
            tabContent: tabContent
        )
    }

    private func tabContent(_ tab: InspectorTabState) -> AnyView? {
        guard tab.entry == .files, let workspaceRoot else { return nil }
        return AnyView(
            TalkifyInspectorFileWorkspace(
                rootURL: workspaceRoot,
                selectedPath: Binding(
                    get: { tab.session.selectedFilePath },
                    set: { tab.session.selectedFilePath = $0 }
                )
            )
        )
    }
}

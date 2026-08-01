//
//  TalkifyInspectorWorkbench.swift
//  Talkify
//
//  Created by Codex on 2026/8/1.
//

import SwiftUI
import AgentKit

/// Talkify 对 AgentKit Inspector 工作台的宿主协调层。
///
/// AgentKit 负责入口、selection 和内部导航；Talkify 负责打开工作区文件浏览器，
/// 并逐步接入终端、浏览器、审阅和侧边聊天的长生命周期资源。
struct TalkifyInspectorWorkbench: View {
    let selection: InspectorSelection?
    let fileProvider: (any AgentKit.FileContentProvider)?
    let usesNavigationStack: Bool
    let workspaceState: InspectorWorkspaceState
    var onOpenFiles: (() -> Void)?

    var body: some View {
        InspectorWorkbenchView(
            selection: selection,
            fileProvider: fileProvider,
            usesNavigationStack: usesNavigationStack,
            workspaceState: workspaceState,
            onOpenEntry: openEntry
        )
    }

    private func openEntry(_ entry: InspectorEntry) {
        if entry == .files, let onOpenFiles {
            onOpenFiles()
        }
    }
}

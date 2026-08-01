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
    var onOpenFiles: (() -> Void)?

    @State private var pendingEntry: InspectorEntry?

    var body: some View {
        Group {
            if selection != nil {
                InspectorWorkbenchView(
                    selection: selection,
                    fileProvider: fileProvider,
                    usesNavigationStack: usesNavigationStack,
                    onOpenEntry: openEntry
                )
            } else if let pendingEntry {
                pendingEntryView(pendingEntry)
            } else {
                InspectorWorkbenchView(
                    selection: nil,
                    fileProvider: fileProvider,
                    usesNavigationStack: usesNavigationStack,
                    onOpenEntry: openEntry
                )
            }
        }
        .onChange(of: selection) { _, newSelection in
            if newSelection != nil {
                pendingEntry = nil
            }
        }
    }

    private func openEntry(_ entry: InspectorEntry) {
        if entry == .files, let onOpenFiles {
            onOpenFiles()
        } else {
            pendingEntry = entry
        }
    }

    private func pendingEntryView(_ entry: InspectorEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    pendingEntry = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回 Inspector")

                Label(entry.title, systemImage: entry.systemImage)
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            Divider()

            ContentUnavailableView(
                "\(entry.title)正在接入",
                systemImage: entry.systemImage,
                description: Text("主入口已经建立，具体会话将在后续阶段接入。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

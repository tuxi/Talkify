#if os(macOS)
import AppKit
import SwiftUI
import AgentKit

extension EnvironmentValues {
    @Entry var openArchivedConversation: ((ConversationRef) -> Void)? = nil
}

struct MacDataManagementSettings: View {
    let allowsFinderReveal: Bool
    @State private var showsArchivedConversations = false

    var body: some View {
        Button {
            showsArchivedConversations = true
        } label: {
            HStack(spacing: 12) {
                Text("已归档的对话")
                    .font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.dataManagement.archive")
        .sheet(isPresented: $showsArchivedConversations) {
            MacArchivedConversationsView(allowsFinderReveal: allowsFinderReveal)
        }
    }
}

private struct MacArchivedConversationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openArchivedConversation) private var openConversation
    @Environment(WorkspaceStore.self) private var store
    let allowsFinderReveal: Bool
    @State private var loadError: String?
    @State private var renameTarget: ConversationRef?
    @State private var renameText = ""
    @State private var deletionTarget: ConversationRef?
    @State private var actionError: String?

    private var list: ConversationListViewModel { store.listViewModel }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("已归档的对话")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider()
            Group {
                if !store.supportsConversationArchive {
                    ContentUnavailableView("当前服务器不支持会话归档", systemImage: "archivebox")
                } else if !list.isLoadingArchived, let loadError {
                    ContentUnavailableView {
                        Label("无法加载归档对话", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("重试") { Task { await loadArchive() } }
                    }
                } else if !list.hasLoadedArchivedConversations {
                    ProgressView("正在加载归档对话…")
                        .controlSize(.small)
                } else if list.archivedConversations.isEmpty && !list.hasMoreArchivedConversations {
                    ContentUnavailableView("没有已归档的对话", systemImage: "archivebox")
                } else {
                    archivedList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 440)
        .task(id: store.supportsConversationArchive) {
            if store.supportsConversationArchive { await loadArchive() }
        }
        .modifier(MacSessionActionDialogs(
            renameTarget: $renameTarget, renameText: $renameText,
            deletionTarget: $deletionTarget, actionError: $actionError
        ))
    }

    private func loadArchive() async {
        loadError = nil
        await list.refreshArchived()
        if !list.hasLoadedArchivedConversations {
            loadError = list.errorMessage
        }
    }

    private var archivedList: some View {
        List {
            ForEach(list.archivedConversationItems) { item in
                archivedRow(item.ref)
            }
            if list.hasMoreArchivedConversations {
                Button {
                    Task {
                        await list.loadMoreConversations(archived: true)
                        if let error = list.errorMessage { actionError = error }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if list.isLoadingMoreArchived { ProgressView().controlSize(.small) }
                        Text("加载更多归档")
                    }
                }
                .disabled(list.isLoadingMoreArchived)
            }
        }
        .listStyle(.inset)
    }

    private func archivedRow(_ ref: ConversationRef) -> some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
                openConversation?(ref)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ref.name.flatMap { $0.isEmpty ? nil : $0 } ?? ref.id)
                        .font(.system(size: 14))
                        .lineLimit(1)
                    Text(ref.workspaceGroupingName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(openConversation == nil)
            Button("Restore") {
                Task {
                    do { try await store.restoreConversation(ref) }
                    catch { actionError = error.localizedDescription }
                }
            }
            .disabled(list.restoringConversationIDs.contains(ref.id) || list.deletingConversationIDs.contains(ref.id))
            Menu {
                Button("Rename") {
                    renameText = ref.name ?? ""
                    renameTarget = ref
                }
                if allowsFinderReveal, ref.workspacePath.hasPrefix("/") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: ref.workspacePath)])
                    }
                }
                Divider()
                Button("Delete…", role: .destructive) { deletionTarget = ref }
                    .disabled(!store.canDeleteConversation(ref) || list.deletingConversationIDs.contains(ref.id)
                              || list.restoringConversationIDs.contains(ref.id))
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("对话操作")
        }
        .padding(.vertical, 4)
    }
}
#endif

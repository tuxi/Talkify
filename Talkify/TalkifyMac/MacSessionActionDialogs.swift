#if os(macOS)
import SwiftUI
import AgentKit

struct MacSessionActionDialogs: ViewModifier {
    @Environment(WorkspaceStore.self) private var store
    @Binding var renameTarget: ConversationRef?
    @Binding var renameText: String
    @Binding var deletionTarget: ConversationRef?
    @Binding var actionError: String?
    @State private var dirtyWorktree: (ref: ConversationRef, summary: ManagedWorktreeDirtySummary?)?

    func body(content: Content) -> some View {
        content
            .alert("重命名对话", isPresented: presented($renameTarget)) {
                TextField("名称", text: $renameText)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    guard let target = renameTarget else { return }
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    Task {
                        if await store.renameConversation(target, name: name) == nil {
                            actionError = store.listViewModel.errorMessage ?? "名称保存失败。"
                        }
                    }
                }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .alert("删除对话？", isPresented: presented($deletionTarget), presenting: deletionTarget) { target in
                Button("取消", role: .cancel) {}
                Button("删除对话", role: .destructive) {
                    delete(target, disposition: .keep)
                }
                if target.worktree?.managed == true {
                    Button("删除对话和 Worktree", role: .destructive) {
                        delete(target, disposition: .remove)
                    }
                }
            } message: { target in
                Text(target.worktree?.managed == true
                     ? "对话历史将永久删除。你可以保留 Worktree，或同时移除它。"
                     : "对话历史将永久删除。")
            }
            .alert("Worktree 包含未保存的更改", isPresented: presented($dirtyWorktree), presenting: dirtyWorktree) { item in
                Button("取消", role: .cancel) {}
                Button("强制删除 Worktree 和对话", role: .destructive) {
                    delete(item.ref, disposition: .remove, force: true)
                }
            } message: { item in
                if let summary = item.summary {
                    Text("检测到 \(summary.modifiedFiles) 个已修改文件、\(summary.untrackedFiles) 个未跟踪文件和 \(summary.newCommits) 个新提交。强制删除会永久移除 Worktree，Git 分支会保留。")
                } else {
                    Text("强制删除会永久移除 Worktree 及其中的未保存更改，Git 分支会保留。")
                }
            }
            .alert("操作失败", isPresented: presented($actionError), presenting: actionError) { _ in
                Button("好", role: .cancel) {}
            } message: { Text($0) }
    }

    private func delete(_ ref: ConversationRef, disposition: ConversationWorktreeDisposition, force: Bool = false) {
        Task {
            do {
                try await store.deleteConversation(ref, worktreeDisposition: disposition, forceWorktreeRemoval: force)
            } catch let error as ManagedWorktreeRemovalError where error.isDirtyConflict && !force {
                dirtyWorktree = (ref, error.summary)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func presented<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
#endif

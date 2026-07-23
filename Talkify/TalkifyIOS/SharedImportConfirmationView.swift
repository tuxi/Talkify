//
//  SharedImportConfirmationView.swift
//  Talkify
//
//  Created by Codex on 2026/7/22.
//

#if os(iOS)
import SwiftUI

struct SharedImportConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    let request: SharedImportInbox.Request
    let onCreate: (String) async throws -> Void
    let onFinished: (SharedImportCompletion) -> Void

    @State private var workspaceName: String
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var confirmsDiscard = false

    init(
        request: SharedImportInbox.Request,
        onCreate: @escaping (String) async throws -> Void,
        onFinished: @escaping (SharedImportCompletion) -> Void
    ) {
        self.request = request
        self.onCreate = onCreate
        self.onFinished = onFinished
        self._workspaceName = State(initialValue: request.suggestedName)
    }

    private var trimmedName: String {
        workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))

                        Text("收到外部资料")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("将这些内容复制为独立工作区，然后你可以补充要求并让 CodeAgent 开始处理。")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("工作区名称")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("工作区名称", text: $workspaceName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 46)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("包含 \(request.items.count) 项")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(request.items.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 10) {
                                Image(systemName: item.isDirectory ? "folder" : "doc")
                                    .foregroundStyle(item.isDirectory ? Color.accentColor : .secondary)
                                    .frame(width: 20)
                                Text(item.name)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button(action: createWorkspace) {
                        HStack(spacing: 8) {
                            if isCreating { ProgressView().tint(.white) }
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                            Text(isCreating ? "正在创建工作区…" : "创建工作区并开始对话")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedName.isEmpty || isCreating)

                    Button("不再导入这些资料", role: .destructive) {
                        confirmsDiscard = true
                    }
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .disabled(isCreating)
                }
                .padding(20)
            }
            .navigationTitle("导入到 CodeAgent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后") {
                        dismiss()
                        onFinished(.deferred)
                    }
                    .disabled(isCreating)
                }
            }
            .interactiveDismissDisabled()
            .confirmationDialog(
                "不再导入这些资料？",
                isPresented: $confirmsDiscard,
                titleVisibility: .visible
            ) {
                Button("删除待导入资料", role: .destructive) {
                    dismiss()
                    onFinished(.discarded)
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("已创建的工作区不会受影响。")
            }
        }
    }

    private func createWorkspace() {
        guard !trimmedName.isEmpty, !isCreating else { return }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                try await onCreate(trimmedName)
                dismiss()
                onFinished(.created)
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

enum SharedImportCompletion {
    case created
    case deferred
    case discarded
}
#endif

//
//  SharedImportConfirmationView.swift
//  Talkify
//
//  Created by Codex on 2026/7/22.
//

#if os(iOS)
import SwiftUI
import CoreKit

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

                        Text(TalkifyLocalized.string("import.external_materials"))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(TalkifyLocalized.string("import.copy_as_workspace"))
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(TalkifyLocalized.string("share.workspace_name"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(TalkifyLocalized.string("share.workspace_name"), text: $workspaceName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 46)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: TalkifyLocalized.string("share.containing_items"), String(request.items.count)))
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
                            Text(isCreating ? TalkifyLocalized.string("import.creating_workspace") : TalkifyLocalized.string("import.create_and_chat"))
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedName.isEmpty || isCreating)

                    Button(TalkifyLocalized.string("import.stop_importing"), role: .destructive) {
                        confirmsDiscard = true
                    }
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .disabled(isCreating)
                }
                .padding(20)
            }
            .navigationTitle(TalkifyLocalized.string("import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TalkifyLocalized.string("import.later")) {
                        dismiss()
                        onFinished(.deferred)
                    }
                    .disabled(isCreating)
                }
            }
            .interactiveDismissDisabled()
            .confirmationDialog(
                TalkifyLocalized.string("import.stop_confirm_title"),
                isPresented: $confirmsDiscard,
                titleVisibility: .visible
            ) {
                Button(TalkifyLocalized.string("import.delete_pending"), role: .destructive) {
                    dismiss()
                    onFinished(.discarded)
                }
                Button(TalkifyLocalized.string("common.action.cancel"), role: .cancel) { }
            } message: {
                Text(TalkifyLocalized.string("import.existing_unaffected"))
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

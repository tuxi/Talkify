#if os(macOS)
import AppKit
import SwiftUI
import AgentKit

struct MacSessionSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let store: WorkspaceStore
    let onSelect: (ConversationRef) -> Void

    @State private var query = ""
    @State private var results: [MacSessionSearchResult] = []
    @State private var highlightedID: String?
    @State private var hoveredID: String?

    private var list: ConversationListViewModel { store.listViewModel }
    private var keyword: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if !keyword.isEmpty && !results.isEmpty {
                            Text("Search results")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        ForEach(results) { result in
                            resultRow(result)
                                .id(result.id)
                        }
                        feedback
                    }
                    .padding(9)
                }
                .onChange(of: highlightedID) { _, id in
                    if let id { scroll.scrollTo(id) }
                }
            }
        }
        .frame(width: 596, height: 448)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("workspace.sessionSearch")
        .onChange(of: query) { _, _ in updateResults(resetHighlight: true) }
        .onChange(of: list.revision, initial: true) { _, _ in updateResults() }
        .task { await loadSessions() }
        .onExitCommand { dismiss() }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            SessionSearchField(
                text: $query,
                onMove: moveHighlight,
                onOpen: openHighlightedResult,
                onClose: { dismiss() }
            )
            .frame(height: 24)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close search")
        }
        .font(.system(size: 14))
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    private func resultRow(_ result: MacSessionSearchResult) -> some View {
        let highlighted = highlightedID == result.id
        return Button { onSelect(result.session) } label: {
            HStack(spacing: 9) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if result.showsPath {
                        Text(result.session.workspacePath)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 12)
                Text(result.session.workspaceGroupingName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 128, alignment: .trailing)
                Image(systemName: "return")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .opacity(highlighted ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(Color.primary.opacity(highlighted ? 0.10 : hoveredID == result.id ? 0.045 : 0),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
        .accessibilityIdentifier("workspace.sessionSearch.result.\(result.id)")
        .onHover { hovering in
            if hovering { hoveredID = result.id }
            else if hoveredID == result.id { hoveredID = nil }
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let error = list.errorMessage {
            Button {
                Task { await loadSessions(refresh: true) }
            } label: {
                Label("Couldn’t load sessions. Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(error)
            .frame(maxWidth: .infinity)
            .padding(12)
        } else if list.isWaitingForRuntime || !list.hasLoadedConversations || list.hasMoreConversations {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading sessions…")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(12)
        } else if results.isEmpty {
            Text(keyword.isEmpty ? "No sessions yet" : "No matching sessions")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
        }
    }

    private func loadSessions(refresh: Bool = false) async {
        if refresh || !list.hasLoadedConversations { await store.refreshConversationList() }
        guard !Task.isCancelled else { return }
        await list.loadRemainingConversations()
    }

    private func updateResults(resetHighlight: Bool = false) {
        results = MacSessionSearchResult.matching(list.conversations, keyword: keyword)
        if resetHighlight || !results.contains(where: { $0.id == highlightedID }) {
            highlightedID = results.first?.id
        }
    }

    private func moveHighlight(by offset: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == highlightedID } ?? 0
        highlightedID = results[min(max(index + offset, 0), results.count - 1)].id
    }

    private func openHighlightedResult() {
        if let result = results.first(where: { $0.id == highlightedID }) ?? results.first {
            onSelect(result.session)
        }
    }
}

/// Delegate commands arrive after the field editor handles marked text.
private struct SessionSearchField: NSViewRepresentable {
    @Binding var text: String
    let onMove: (Int) -> Void
    let onOpen: () -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchField {
        let field = SearchField()
        let placeholder = String(localized: "Search sessions and projects")
        field.placeholderString = placeholder
        field.stringValue = text
        field.font = .systemFont(ofSize: 14)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        field.setAccessibilityIdentifier("workspace.sessionSearch.query")
        return field
    }

    func updateNSView(_ field: SearchField, context: Context) {
        context.coordinator.parent = self
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if field.stringValue != text && !composing { field.stringValue = text }
    }

    final class SearchField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SessionSearchField

        init(_ parent: SessionSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch command {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onOpen()
            case #selector(NSResponder.cancelOperation(_:)): parent.onClose()
            default: return false
            }
            return true
        }
    }
}

struct MacSessionSearchResult: Identifiable {
    let session: ConversationRef
    var showsPath = false
    var id: String { session.id }
    var title: String { session.name.flatMap { $0.isEmpty ? nil : $0 } ?? session.id }

    static func matching(_ sessions: [ConversationRef], keyword: String) -> [Self] {
        guard !keyword.isEmpty else { return sessions.map { Self(session: $0) } }
        var titleMatches: [Self] = []
        var workspaceMatches: [Self] = []
        var pathAndIDMatches: [Self] = []
        // Preserve the runtime's recency order within each match category.
        for session in sessions {
            let result = Self(session: session)
            if result.title.localizedCaseInsensitiveContains(keyword) {
                titleMatches.append(result)
            } else if session.workspaceGroupingName.localizedCaseInsensitiveContains(keyword) {
                workspaceMatches.append(result)
            } else if session.workspacePath.localizedCaseInsensitiveContains(keyword) {
                pathAndIDMatches.append(Self(session: session, showsPath: true))
            } else if session.id.localizedCaseInsensitiveContains(keyword) {
                pathAndIDMatches.append(result)
            }
        }
        return titleMatches + workspaceMatches + pathAndIDMatches
    }
}
#endif

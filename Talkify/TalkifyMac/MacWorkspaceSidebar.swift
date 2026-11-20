#if os(macOS)
import AppKit
import SwiftUI
import AgentKit

struct MacWorkspaceSidebar: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("workspace.sidebar.routines") private var pinsRoutines = false
    @AppStorage("workspace.sidebar.customize") private var pinsCustomize = true
    @Binding var showsCustomize: Bool
    @Binding var expandedGroups: Set<String>
    let allowsFinderReveal: Bool
    let onSearch: () -> Void
    let onOpenCodingTasks: () -> Void
    let onSelectSession: (ConversationRef) -> Void

    @State private var groups: [MacSidebarWorkspace] = []
    @State private var showsMore = false
    @State private var hoveringMore = false
    @State private var showsEditor = false
    @State private var editRoutines = false
    @State private var editCustomize = true
    @State private var renameTarget: ConversationRef?
    @State private var renameText = ""
    @State private var deletionTarget: ConversationRef?
    @State private var actionError: String?

    private var list: ConversationListViewModel { store.listViewModel }
    private var selectedID: String? {
        guard !showsCustomize, case let .conversationDetail(ref) = store.selectItem else { return nil }
        return ref.id
    }
    private var showsRoutines: Bool { !showsCustomize && store.selectItem == .automation }

    var body: some View {
        VStack(spacing: 0) {
            shortcuts.padding(.bottom, 14)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        listFeedback
                        ForEach(groups) { group in
                            workspaceRows(group)
                        }
                        if list.hasMoreConversations { loadMore }
                    }
                    .padding(.bottom, 10)
                }
                .task(id: selectedID) {
                    guard let id = selectedID else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if let group = groups.first(where: { $0.sessions.contains { $0.id == id } }),
                       !expandedGroups.contains(group.id) {
                        scroll.scrollTo(group.id)
                    } else {
                        scroll.scrollTo(id)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("workspace.sidebar")
        .onChange(of: list.revision, initial: true) { _, _ in rebuildGroups() }
        .onChange(of: store.recentWorkspaces.workspaces) { _, _ in rebuildGroups() }
        .onChange(of: store.projects.projects) { _, _ in rebuildGroups() }
        .onChange(of: store.selectedConversation?.presentationID, initial: true) { _, _ in
            // A directly opened session may be outside the loaded page.
            rebuildGroups()
        }
        .sheet(isPresented: $showsEditor) { editor }
        .modifier(MacSessionActionDialogs(
            renameTarget: $renameTarget, renameText: $renameText,
            deletionTarget: $deletionTarget, actionError: $actionError
        ))
    }

    private var shortcuts: some View {
        VStack(spacing: 2) {
            shortcut("New", symbol: "plus") { store.beginDraft() }
            shortcut("Search", symbol: "magnifyingglass", action: onSearch)
                .keyboardShortcut("f", modifiers: .command)
            if pinsRoutines { routinesShortcut }
            if pinsCustomize { customizeShortcut }
            if !pinsRoutines || !pinsCustomize {
                let currentTitle = showsRoutines && !pinsRoutines ? "Routines"
                    : showsCustomize && !pinsCustomize ? "Customize" : "More"
                shortcut(currentTitle, symbol: "ellipsis", selected: currentTitle != "More") {
                    showsMore = true
                }
                .accessibilityLabel("More")
                .onHover { hoveringMore = $0 }
                .task(id: hoveringMore) {
                    guard hoveringMore else { return }
                    do { try await Task.sleep(for: .milliseconds(320)) } catch { return }
                    showsMore = true
                }
                .popover(isPresented: $showsMore, arrowEdge: .trailing) {
                    VStack(spacing: 2) {
                        if !pinsRoutines { routinesShortcut }
                        if !pinsCustomize { customizeShortcut }
                        Divider().padding(.vertical, 3)
                        shortcut("Edit sidebar…", symbol: "slider.horizontal.3") { openEditor() }
                    }
                    .padding(5)
                    .frame(width: 166)
                }
            }
        }
        .contextMenu {
            Button("Edit sidebar…") { openEditor() }
            Divider()
            Button("Workflows") {
                showsCustomize = false
                store.selectItem = .workflow
            }
            Button("协作任务", systemImage: "person.3.sequence", action: onOpenCodingTasks)
        }
    }

    private var routinesShortcut: some View {
        shortcut("Routines", symbol: "clock", selected: showsRoutines) {
            showsMore = false
            showsCustomize = false
            store.selectItem = .automation
        }
    }

    private var customizeShortcut: some View {
        shortcut("Customize", symbol: "briefcase", selected: showsCustomize) {
            showsMore = false
            store.selectItem = .draft
            showsCustomize = true
        }
    }

    private func shortcut(_ title: String, symbol: String, selected: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 17)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14))
            .padding(.horizontal, 8)
            .frame(height: 29)
            .modifier(MacSidebarHighlight(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Edit sidebar").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { showsEditor = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("关闭")
                    .keyboardShortcut(.cancelAction)
            }
            Text("Choose which items appear in your sidebar.")
                .foregroundStyle(.secondary)
            Toggle(isOn: $editRoutines) { Label("Routines", systemImage: "clock") }
            Toggle(isOn: $editCustomize) { Label("Customize", systemImage: "briefcase") }
            HStack {
                Spacer()
                Button("Done") {
                    pinsRoutines = editRoutines
                    pinsCustomize = editCustomize
                    showsEditor = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .toggleStyle(.checkbox)
        .padding(20)
        .frame(width: 340)
    }

    private func openEditor() {
        showsMore = false
        editRoutines = pinsRoutines
        editCustomize = pinsCustomize
        showsEditor = true
    }

    @ViewBuilder
    private func workspaceRows(_ group: MacSidebarWorkspace) -> some View {
        let expanded = expandedGroups.contains(group.id)
        workspaceHeader(group, expanded: expanded)
            .id(group.id)
        ForEach(group.visibleSessions(expanded: expanded, selectedID: selectedID, activity: store.supervisor.activity(for:))) { ref in
            sessionRow(ref)
                .id(ref.id)
        }
    }

    private func workspaceHeader(_ group: MacSidebarWorkspace, expanded: Bool) -> some View {
        MacSidebarWorkspaceHeader(title: group.title, expanded: expanded) {
            if expanded { expandedGroups.remove(group.id) }
            else { expandedGroups.insert(group.id) }
        } onCreate: {
            newSession(in: group)
        }
        .help(group.path.isEmpty ? group.title : group.path)
        .contextMenu {
            Button("New session") { newSession(in: group) }
            if allowsFinderReveal && group.path.hasPrefix("/") {
                Button("Show in Finder") { reveal(group.path) }
            }
            Divider()
            Button("Collapse all") { expandedGroups.removeAll() }
            Button("Expand all") { expandedGroups = Set(groups.map(\.id)) }
        }
    }

    private func sessionRow(_ ref: ConversationRef) -> some View {
        MacSidebarSessionRow(
            ref: ref, selected: ref.id == selectedID,
            activity: store.supervisor.activity(for: ref), reduceMotion: reduceMotion
        ) {
            onSelectSession(ref)
        } actions: {
            sessionActions(ref)
        }
    }

    @ViewBuilder
    private func sessionActions(_ ref: ConversationRef) -> some View {
        if allowsFinderReveal && ref.workspacePath.hasPrefix("/") {
            Button("Show in Finder") { reveal(ref.workspacePath) }
        }
        Button("Rename") {
            let current = list.conversations.first { $0.id == ref.id } ?? ref
            renameTarget = current
            renameText = current.name ?? ""
        }
        if store.supportsConversationForkThroughTurn {
            Button("Fork") { perform { _ = try await store.forkConversation(from: ref, throughTurnID: nil) } }
        }
        if store.supportsConversationArchive {
            Divider()
            Button("Archive") {
                perform { _ = try await store.archiveConversation(ref) }
            }
            .disabled(!store.canArchiveConversation(ref) || list.archivingConversationIDs.contains(ref.id))
        }
        Divider()
        Button("Delete…", role: .destructive) { deletionTarget = ref }
            .disabled(!store.canDeleteConversation(ref) || list.deletingConversationIDs.contains(ref.id))
    }

    @ViewBuilder
    private var listFeedback: some View {
        if !list.hasLoadedConversations && (list.isLoading || list.isWaitingForRuntime) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(list.isWaitingForRuntime ? "正在连接 Runtime…" : "正在加载对话…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }
        if let error = list.errorMessage {
            Button {
                Task { await store.refreshConversationList() }
            } label: {
                Label("加载失败，点击重试", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help(error)
        }
    }

    private var loadMore: some View {
        Button {
            Task { await list.loadMoreConversations() }
        } label: {
            HStack {
                if list.isLoadingMore { ProgressView().controlSize(.mini) }
                Text("加载更早对话")
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
        .disabled(list.isLoadingMore)
    }

    private func rebuildGroups() {
        var sessions = list.conversations
        if let selected = store.selectedConversation, selected.id == selectedID,
           !selected.isArchived, !sessions.contains(where: { $0.id == selected.id }) {
            sessions.insert(selected, at: 0)
        }
        groups = MacSidebarWorkspace.grouped(
            sessions: sessions,
            workspaces: store.recentWorkspaces.workspaces + store.projects.projects,
            resolvesLocalAliases: allowsFinderReveal
        )
    }

    private func newSession(in group: MacSidebarWorkspace) {
        store.beginDraft()
        if group.path.hasPrefix("/") {
            let url = URL(fileURLWithPath: group.path, isDirectory: true)
            store.selectWorkspace(group.workspace ?? Workspace(url: url))
        }
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path, isDirectory: true)])
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await operation() }
            catch { actionError = error.localizedDescription }
        }
    }
}

struct MacSidebarWorkspace: Identifiable {
    let id: String
    let title: String
    let path: String
    var workspace: Workspace? = nil
    var sessions: [ConversationRef] = []

    func visibleSessions(expanded: Bool, selectedID: String?,
                         activity: (ConversationRef) -> ConversationActivityState) -> [ConversationRef] {
        if expanded { return sessions }
        return sessions.filter { $0.id == selectedID || activity($0).keepsSidebarRowVisible }
    }

    static func grouped(sessions: [ConversationRef], workspaces: [Workspace],
                        resolvesLocalAliases: Bool = false) -> [Self] {
        let projects = workspaces.map { (workspace: $0, id: "path:\($0.url.canonicalPathForGrouping)") }
        let entries = sessions.map { (ref: $0, id: $0.workspaceGroupingID) }
        let aliases = resolvesLocalAliases ? localPathAliases(projects.map(\.id) + entries.map(\.id)) : [:]
        var groups: [String: Self] = [:]
        for (workspace, key) in projects {
            let id = aliases[key] ?? key
            if groups[id] == nil {
                groups[id] = Self(id: id, title: workspace.name, path: workspace.url.path, workspace: workspace)
            }
        }
        for (ref, key) in entries {
            let id = aliases[key] ?? key
            let path = id.hasPrefix("path:") ? String(id.dropFirst(5)) : ref.workspacePath
            let title = aliases[key] == nil ? ref.workspaceGroupingName : URL(fileURLWithPath: path).lastPathComponent
            groups[id, default: Self(id: id, title: title, path: path)].sessions.append(ref)
        }
        return groups.values.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    private static func localPathAliases(_ keys: [String]) -> [String: String] {
        let paths = Set(keys.filter { $0.hasPrefix("path:/") })
        let candidates = Dictionary(grouping: paths) { $0.lowercased() }
        var aliases: [String: String] = [:]
        // Only inspect case collisions. realpath preserves distinct directories
        // on case-sensitive volumes and resolves aliases on local APFS.
        for collision in candidates.values where collision.count > 1 {
            for key in collision {
                guard let resolved = realpath(String(key.dropFirst(5)), nil) else { continue }
                aliases[key] = "path:\(String(cString: resolved))"
                free(resolved)
            }
        }
        return aliases
    }
}

extension ConversationActivityState {
    var keepsSidebarRowVisible: Bool {
        switch self {
        case .connecting, .queued, .running, .waitingForApproval, .waitingForClientTool,
             .waitingForBackground, .backgroundNeedsAttention: true
        case .paused, .succeeded, .failed, .cancelled, .idle: false
        }
    }
}

private struct MacSidebarHighlight: ViewModifier {
    let selected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(selected ? 0.115 : hovering ? 0.05 : 0),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

private struct MacSidebarWorkspaceHeader: View {
    let title: String
    let expanded: Bool
    let onToggle: () -> Void
    let onCreate: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Text(title).lineLimit(1)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .frame(height: 29)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "已展开" : "已收起")
            if hovering {
                Button(action: onCreate) {
                    Image(systemName: "plus").frame(width: 23, height: 25)
                }
                .buttonStyle(.plain)
                .help("在 \(title) 中新建对话")
                .accessibilityLabel("在 \(title) 中新建对话")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct MacSidebarSessionRow<Actions: View>: View {
    let ref: ConversationRef
    let selected: Bool
    let activity: ConversationActivityState
    let reduceMotion: Bool
    let onSelect: () -> Void
    @ViewBuilder let actions: () -> Actions
    @State private var hovering = false

    private var title: String { ref.displayTitle }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onSelect) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(activityLabel)

            if selected || hovering {
                Menu(content: actions) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 20, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("对话操作")
            } else if activity == .failed || activity == .backgroundNeedsAttention {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .help(activityLabel)
                    .accessibilityHidden(true)
            } else if activity.keepsSidebarRowVisible {
                MacSidebarActivityDot(reduceMotion: reduceMotion)
                    .frame(width: 20)
                    .help(activityLabel)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .modifier(MacSidebarHighlight(selected: selected))
        .onHover { hovering = $0 }
        .contextMenu(menuItems: actions)
        .help(title)
        .accessibilityIdentifier("workspace.sidebar.session.\(ref.id)")
    }

    private var activityLabel: String {
        switch activity {
        case .connecting: "连接中"
        case .queued: "排队中"
        case .running: "执行中"
        case .waitingForApproval: "等待审批"
        case .waitingForClientTool: "等待客户端"
        case .waitingForBackground: "等待后台结果"
        case .backgroundNeedsAttention: "需要处理"
        case .paused: "已暂停"
        case .succeeded: "已完成"
        case .failed: "执行失败"
        case .cancelled: "已取消"
        case .idle: ""
        }
    }
}

private struct MacSidebarActivityDot: View {
    let reduceMotion: Bool
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: 5, height: 5)
            .opacity(reduceMotion ? 0.8 : dimmed ? 0.35 : 0.95)
            .task(id: reduceMotion) {
                dimmed = false
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}
#endif

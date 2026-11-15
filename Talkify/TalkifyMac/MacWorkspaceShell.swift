#if os(macOS)
import SwiftUI
import AppKit
import AgentKit
import FileViewerKit

/// macOS owns its pane geometry; the system inspector is only used on iOS/iPad.
struct MacWorkspaceShell<Sidebar: View, Content: View, Inspector: View>: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let pageID: String
    let isConversation: Bool
    let supportsInspector: Bool
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let content: () -> Content
    @ViewBuilder let inspector: (MacWorkspaceLayout.Panel) -> Inspector

    @State private var layout = MacWorkspaceLayout()
    @State private var showsSidebarOverlay = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var panelDragWidth: CGFloat?
    @State private var sidebarDragWidth: CGFloat?
    @State private var retainedTools: Set<MacWorkspaceLayout.Panel> = [.sessionRail]

    var body: some View {
        GeometryReader { geometry in
            let projection = layout.project(width: geometry.size.width, supportsInspector: supportsInspector)
            HStack(spacing: 0) {
                sidebarPane
                    .frame(width: layout.sidebarWidth)
                    .frame(width: projection.sidebarWidth, alignment: .leading)
                    .clipped()
                    .allowsHitTesting(projection.showsSidebar)
                    .accessibilityHidden(!projection.showsSidebar)
                sidebarResizeHandle
                    .frame(width: projection.showsSidebar ? 1 : 0)
                    .opacity(projection.showsSidebar ? 1 : 0)
                    .allowsHitTesting(projection.showsSidebar)
                    .accessibilityHidden(!projection.showsSidebar)
                workspace(projection: projection)
                    .frame(width: projection.workspaceWidth)
            }
            .overlay(alignment: .leading) {
                if showsSidebarOverlay && !projection.showsSidebar {
                    ZStack(alignment: .leading) {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { dismissSidebar() }
                        sidebarPane
                            .frame(width: min(layout.sidebarWidth, max(0, geometry.size.width - 40)))
                            .background(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.14), radius: 14, x: 6)
                            .onHover { hovering in
                                if hovering { hoverTask?.cancel() } else { scheduleSidebarDismiss() }
                            }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                if projection.floatsRail {
                    ZStack(alignment: .topTrailing) {
                        // The header remains interactive; the popup never changes column widths.
                        MacWorkspaceSessionRail { inspector(.sessionRail) }
                            .environment(\.sessionRailIsVisible, true)
                            .frame(width: projection.panelWidth)
                            .frame(maxHeight: .infinity)
                            .background(MacWorkspaceOutsideInteractionDismissal { dismissFloatingRail() })
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.14), radius: 12, y: 3)
                            .padding(8)
                    }
                    .padding(.top, 46)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .accessibilityIdentifier("workspace.sessionRail.floating")
                }
            }
            // Only discrete presentation changes animate. Live drag widths follow the pointer.
            .animation(paneAnimation, value: projection.presentation)
            .animation(paneAnimation, value: projection.showsSidebar)
            .animation(paneAnimation, value: showsSidebarOverlay)
            .onChange(of: projection.presentation) { _, presentation in
                if presentation == .docked, layout.panel == .sessionRail { layout.didDockRail() }
            }
            .onChange(of: projection.showsSidebar) { _, shown in
                if shown { dismissSidebar() }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: pageID, initial: true) { _, _ in
            dismissSidebar()
            layout.selectPage(isConversation: isConversation)
            if supportsInspector {
                store.dismissInspector()
                store.isInspectorPresented = layout.panel != nil
            }
        }
        .onChange(of: store.inspectorSelection) { _, selection in
            guard supportsInspector, selection != nil else { return }
            if layout.panel != .detail { layout.panelBeforeTool = layout.panel }
            layout.panel = .detail
            retainedTools.insert(.detail)
            layout.isFocused = false
            layout.dismissFloatingRail()
        }
        .onChange(of: store.isInspectorPresented) { _, presented in
            guard supportsInspector else { return }
            if store.inspectorSelection == nil, presented == (layout.panel != nil) { return }
            if presented {
                if store.inspectorSelection != nil {
                    if layout.panel != .detail { layout.panelBeforeTool = layout.panel }
                    layout.panel = .detail
                    retainedTools.insert(.detail)
                    layout.isFocused = false
                } else if layout.panel == nil {
                    layout.panel = .sessionRail
                }
            } else if layout.panel == .detail {
                layout.closePanel()
            } else {
                layout.panel = nil
                layout.isFocused = false
                layout.dismissFloatingRail()
            }
        }
        .onExitCommand {
            dismissSidebar()
            dismissFloatingRail()
        }
        .onDisappear { hoverTask?.cancel() }
    }

    private var paneAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    private var sidebarResizeHandle: some View {
        resizeHandle(label: "调整侧栏宽度", value: layout.sidebarWidth) { translation, ended in
            let initial = sidebarDragWidth ?? layout.sidebarWidth
            sidebarDragWidth = initial
            layout.sidebarWidth = min(320, max(200, initial + translation))
            if ended { sidebarDragWidth = nil }
        }
    }

    private var sidebarPane: some View {
        VStack(spacing: 0) {
            HStack {
                paneButton("收起侧栏", symbol: "sidebar.left") {
                    layout.sidebarPreferred = false
                    dismissSidebar()
                    dismissFloatingRail()
                }
                Spacer()
            }
            .padding(.leading, 78)
            .padding(.trailing, 12)
            .frame(height: 46)
            .background(MacWorkspaceHeaderDragArea(onMouseDown: { dismissFloatingRail() }))
            sidebar()
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func workspace(projection: MacWorkspaceLayout.Projection) -> some View {
        let tool = layout.panel ?? .sessionRail
        let docked = projection.presentation == .docked || projection.isFocused
        let toolHeaderWidth = docked && tool != .sessionRail ? projection.panelWidth : 0
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                conversationHeader(projection: projection)
                    .frame(width: projection.headerWidth)
                    .clipped()
                    .accessibilityHidden(projection.isFocused)
                Color(nsColor: .separatorColor)
                    .frame(width: toolHeaderWidth > 0 && !projection.isFocused ? 1 : 0)
                toolHeader(tool, projection: projection)
                    .frame(width: toolHeaderWidth)
                    .clipped()
                    .allowsHitTesting(toolHeaderWidth > 0)
                    .accessibilityHidden(toolHeaderWidth == 0)
            }
            .frame(height: 46)
            Divider()
            GeometryReader { bodyGeometry in
                ZStack(alignment: .leading) {
                    // Keep the same navigation/timeline subtree throughout resizing and focus.
                    content()
                        .frame(width: projection.mainWidth, height: bodyGeometry.size.height)
                        .clipped()
                        .allowsHitTesting(!projection.isFocused)
                        .accessibilityHidden(projection.isFocused)
                    ForEach(MacWorkspaceLayout.Panel.allCases.filter { retainedTools.contains($0) }, id: \.self) { retained in
                        MacInspectorContentSurface {
                            if retained == .sessionRail {
                                MacWorkspaceSessionRail { inspector(.sessionRail) }
                            } else {
                                inspector(retained)
                            }
                        }
                        .frame(width: retained == tool && docked ? projection.panelWidth : (layout.widths[retained] ?? retained.defaultWidth),
                               height: bodyGeometry.size.height)
                        .clipped()
                        .offset(x: projection.isFocused ? 0 : projection.mainWidth + (docked ? 1 : 0))
                        .opacity(retained == tool && docked ? 1 : 0)
                        .allowsHitTesting(retained == tool && docked)
                        .disabled(retained != tool || !docked)
                        .accessibilityHidden(retained != tool || !docked)
                        .accessibilityIdentifier("workspace.inspector.\(retained.rawValue)")
                        .environment(\.sessionRailIsVisible, retained == .sessionRail && retained == tool && docked)
                    }
                    resizeHandle(label: "调整\(tool.title)宽度", value: projection.panelWidth, reversesDrag: true) { translation, ended in
                        let initial = panelDragWidth ?? projection.panelWidth
                        panelDragWidth = initial
                        layout.resizePanel(to: initial - translation)
                        if ended { panelDragWidth = nil }
                    }
                    .frame(height: bodyGeometry.size.height)
                    .offset(x: projection.mainWidth)
                    .opacity(docked && !projection.isFocused ? 1 : 0)
                    .allowsHitTesting(docked && !projection.isFocused)
                    .accessibilityHidden(!docked || projection.isFocused)
                }
                .frame(width: projection.workspaceWidth, height: bodyGeometry.size.height, alignment: .leading)
                .clipped()
            }
        }
    }

    private func conversationHeader(projection: MacWorkspaceLayout.Projection) -> some View {
        headerRow(projection: projection, compact: projection.headerWidth < (projection.showsSidebar ? 340 : 420))
        .padding(.leading, projection.showsSidebar ? 12 : 78)
        .padding(.trailing, 12)
        .frame(height: 46)
        .background(MacWorkspaceHeaderDragArea(onMouseDown: { dismissFloatingRail() }))
    }

    private func headerRow(projection: MacWorkspaceLayout.Projection, compact: Bool) -> some View {
        HStack(spacing: 8) {
            if !projection.showsSidebar {
                paneButton("显示侧栏", symbol: "sidebar.left") {
                    dismissFloatingRail()
                    var expanded = layout
                    expanded.sidebarPreferred = true
                    if expanded.project(width: projection.windowWidth, supportsInspector: supportsInspector).showsSidebar {
                        layout.sidebarPreferred = true
                    } else {
                        showsSidebarOverlay.toggle()
                    }
                }
                .onHover { hovering in
                    hoverTask?.cancel()
                    if hovering {
                        hoverTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            guard !Task.isCancelled else { return }
                            showsSidebarOverlay = true
                        }
                    } else { scheduleSidebarDismiss() }
                }
            }
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
                .help(title)
                .allowsHitTesting(false)
            if supportsInspector {
                ForEach(visibleEntries(compact: compact, projection: projection), id: \.self) { panel in
                    entryButton(panel, projection: projection)
                }
                Menu {
                    ForEach(availableEntries, id: \.self) { panel in
                        Button { open(panel, width: projection.windowWidth) } label: {
                            Label(panel.title, systemImage: panel.symbol)
                        }
                    }
                    Divider()
                    ConversationWorkspaceActions(hasConversation: isConversation)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("更多工具")
                .simultaneousGesture(TapGesture().onEnded { dismissFloatingRail() })
            }
        }
    }

    private var availableEntries: [MacWorkspaceLayout.Panel] {
        isConversation ? [.sessionRail, .terminal, .changes, .browser, .files] : [.terminal, .files]
    }

    private func visibleEntries(compact: Bool, projection: MacWorkspaceLayout.Projection) -> [MacWorkspaceLayout.Panel] {
        guard compact else { return availableEntries }
        if projection.headerWidth < (projection.showsSidebar ? 260 : 330) {
            return availableEntries.filter { projection.isSelected($0) }
        }
        return availableEntries.filter { $0 == .sessionRail || projection.isSelected($0) }
    }

    private func entryButton(_ panel: MacWorkspaceLayout.Panel, projection: MacWorkspaceLayout.Projection) -> some View {
        paneButton(panel.title, symbol: panel.symbol) { open(panel, width: projection.windowWidth) }
            .background(projection.isSelected(panel) ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .accessibilityAddTraits(projection.isSelected(panel) ? .isSelected : [])
            .accessibilityIdentifier("workspace.entry.\(panel.rawValue)")
            .overlay(alignment: .topTrailing) {
                if panel == .sessionRail, store.sessionRailActivityCount > 0 {
                    Text(store.sessionRailActivityCount > 9 ? "9+" : String(store.sessionRailActivityCount))
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 3)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                        .allowsHitTesting(false)
                        .accessibilityLabel("有后台活动")
                }
            }
    }

    private func toolHeader(_ panel: MacWorkspaceLayout.Panel, projection: MacWorkspaceLayout.Projection) -> some View {
        MacInspectorPaneHeader(
            title: inspectorTitle(panel, width: projection.panelWidth),
            paneTitle: panel.title,
            backLabel: backLabel(panel, width: projection.panelWidth),
            canReturnToRoot: panel == .detail && store.inspectorWorkspaceState.selectionPathState.path.count > 1,
            isFocused: projection.isFocused,
            leadingInset: projection.isFocused && !projection.showsSidebar ? 78 : 12,
            onBack: { navigateBack(panel) },
            onRoot: { store.inspectorWorkspaceState.selectionPathState.popToRoot() },
            onShowSidebar: { showsSidebarOverlay.toggle() },
            onToggleFocus: { layout.isFocused.toggle() },
            onClose: { closePanel() },
            onDrag: { dismissFloatingRail() }
        )
    }

    private func tab(for panel: MacWorkspaceLayout.Panel) -> InspectorTabState? {
        let entry: InspectorEntry
        switch panel {
        case .files: entry = .files
        case .changes: entry = .review
        default: return nil
        }
        return store.inspectorWorkspaceState.tabs.first { $0.entry == entry }
    }

    private func backLabel(_ panel: MacWorkspaceLayout.Panel, width: CGFloat) -> String? {
        switch panel {
        case .files where width < WorkspacePresentation.filesSplitMinimumWidth:
            return tab(for: panel)?.session.selectedFilePath != nil ? "返回文件列表" : nil
        case .changes where width < WorkspacePresentation.reviewSplitMinimumWidth:
            return tab(for: panel)?.session.selectedReviewFilePath != nil ? "返回变更列表" : nil
        case .detail:
            return store.inspectorWorkspaceState.selectionPathState.path.isEmpty ? nil : "返回上一层"
        default: return nil
        }
    }

    private func inspectorTitle(_ panel: MacWorkspaceLayout.Panel, width: CGFloat) -> String {
        if panel == .files, width < WorkspacePresentation.filesSplitMinimumWidth,
           let path = tab(for: panel)?.session.selectedFilePath {
            return (path as NSString).lastPathComponent
        }
        guard panel == .detail,
              let destination = store.inspectorWorkspaceState.selectionPathState.path.last else { return panel.title }
        switch destination {
        case .toolResult: return "工具结果"
        case .filePreview(let path), .diffPreview(let path, _): return (path as NSString).lastPathComponent
        case .agentStateDetail: return "Agent 状态"
        case .assetDetail: return "资源详情"
        case .uiEvidence: return "界面证据"
        case .uiLayout: return "界面布局"
        case .uiPreview: return "界面预览"
        }
    }

    private func navigateBack(_ panel: MacWorkspaceLayout.Panel) {
        switch panel {
        case .files: tab(for: panel)?.session.selectedFilePath = nil
        case .changes: tab(for: panel)?.session.selectedReviewFilePath = nil
        case .detail: store.inspectorWorkspaceState.selectionPathState.pop()
        default: break
        }
    }

    private func paneButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func resizeHandle(label: String, value: CGFloat, reversesDrag: Bool = false, onDrag: @escaping (CGFloat, Bool) -> Void) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Color.clear.frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                    }
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { onDrag($0.translation.width, false) }
                        .onEnded { onDrag($0.translation.width, true) })
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(Int(value))")
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat = direction == .increment ? 20 : -20
                onDrag(reversesDrag ? -delta : delta, true)
            }
    }

    private func open(_ panel: MacWorkspaceLayout.Panel, width: CGFloat) {
        dismissSidebar()
        if store.inspectorSelection != nil { store.dismissInspector() }
        layout.open(panel, availableWidth: width)
        retainedTools.insert(panel)
        store.isInspectorPresented = layout.panel != nil
        switch panel {
        case .terminal: store.inspectorWorkspaceState.open(.terminal)
        case .changes: store.inspectorWorkspaceState.open(.review)
        case .browser: store.inspectorWorkspaceState.open(.browser)
        case .files: store.inspectorWorkspaceState.open(.files)
        default: break
        }
    }

    private func closePanel() {
        layout.closePanel()
        if store.inspectorSelection != nil { store.dismissInspector() }
        store.isInspectorPresented = layout.panel != nil
    }

    private func dismissFloatingRail() {
        layout.dismissFloatingRail()
    }

    private func dismissSidebar() {
        hoverTask?.cancel()
        showsSidebarOverlay = false
    }

    private func scheduleSidebarDismiss() {
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            showsSidebarOverlay = false
        }
    }
}
#endif

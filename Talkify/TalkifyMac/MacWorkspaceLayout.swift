import Foundation

/// Window-local presentation preferences. Geometry never changes user intent.
struct MacWorkspaceLayout {
    enum Panel: String, CaseIterable {
        case sessionRail, terminal, changes, browser, files, detail

        var title: String {
            switch self {
            case .sessionRail: "Session rail"
            case .terminal: "Terminal"
            case .changes: "Changes"
            case .browser: "Browser"
            case .files: "Files"
            case .detail: "详情"
            }
        }

        var symbol: String {
            switch self {
            case .sessionRail: "list.bullet"
            case .terminal: "terminal"
            case .changes: "plus.rectangle.on.folder"
            case .browser: "globe"
            case .files: "folder"
            case .detail: "info.circle"
            }
        }

        var minimumWidth: CGFloat { self == .sessionRail ? 280 : 360 }
        var defaultWidth: CGFloat {
            switch self {
            case .sessionRail: 320
            case .terminal: 520
            case .changes, .browser: 560
            case .files, .detail: 440
            }
        }
        var maximumWidth: CGFloat {
            switch self {
            case .sessionRail: 420
            case .changes, .browser: 960
            default: 800
            }
        }
    }

    /// Restoring another conversation's saved flag is not a close/open action
    /// on the current page. Observe identity and visibility as a single value.
    struct InspectorState: Equatable {
        let pageID: String
        let isPresented: Bool

        func isVisibilityChange(from previous: Self) -> Bool {
            pageID == previous.pageID && isPresented != previous.isPresented
        }
    }

    enum Presentation: Equatable {
        case hidden, docked, floatingRail, focused
    }

    struct Projection {
        var windowWidth: CGFloat
        var sidebarWidth: CGFloat
        var panelWidth: CGFloat
        var mainWidth: CGFloat
        var presentation: Presentation
        var activePanel: Panel?
        var showsSidebar: Bool { sidebarWidth > 0 }
        var showsPanel: Bool { presentation != .hidden }
        var isFocused: Bool { presentation == .focused }
        var floatsRail: Bool { presentation == .floatingRail }
        var workspaceWidth: CGFloat { max(0, windowWidth - sidebarWidth - (showsSidebar ? 1 : 0)) }
        var headerWidth: CGFloat {
            if activePanel == .sessionRail || !showsPanel { return workspaceWidth }
            return isFocused ? 0 : mainWidth
        }
        func isSelected(_ panel: Panel) -> Bool { showsPanel && activePanel == panel }
    }

    /// Keep the narrow workspace usable while retaining the floating rail layout.
    static let windowMinimumWidth: CGFloat = 600
    static let windowMinimumHeight: CGFloat = 700
    static let mainMinimum: CGFloat = 440
    static let compactMainMinimum: CGFloat = 280
    static let compactToolMinimum: CGFloat = 240
    var sidebarPreferred = true
    var sidebarWidth: CGFloat = 240
    var panel: Panel?
    var panelBeforeTool: Panel?
    /// Only the expand button enters focus mode; opening a tool never hides the conversation.
    var isFocused = false
    var railOverlayRequested = false
    private var railPreservesSidebar = false
    var widths: [Panel: CGFloat] = [:]

    mutating func selectPage(isConversation: Bool) {
        panel = isConversation ? .sessionRail : nil
        panelBeforeTool = nil
        isFocused = false
        railOverlayRequested = false
        railPreservesSidebar = false
    }

    mutating func open(_ next: Panel, availableWidth: CGFloat) {
        if next == .sessionRail {
            let current = project(width: availableWidth, supportsInspector: true)
            if current.isSelected(.sessionRail) {
                closePanel()
                return
            }
            panel = .sessionRail
            panelBeforeTool = nil
            isFocused = false
            railPreservesSidebar = current.showsSidebar
            let preservedSidebar = railPreservesSidebar && sidebarPreferred ? sidebarWidth + 1 : 0
            railOverlayRequested = availableWidth < preservedSidebar + Self.mainMinimum + next.minimumWidth + 1
            return
        }
        if panel == next {
            closePanel()
            return
        }
        showTool(next)
    }

    /// Content navigation reveals a tool; repeated opens never toggle it closed.
    mutating func showTool(_ next: Panel) {
        if panel == .sessionRail || panel == nil { panelBeforeTool = panel }
        panel = next
        isFocused = false
        railOverlayRequested = false
        railPreservesSidebar = false
    }

    mutating func closePanel() {
        panel = panel == .sessionRail ? nil : panelBeforeTool
        panelBeforeTool = nil
        isFocused = false
        railOverlayRequested = false
        railPreservesSidebar = false
    }

    mutating func dismissFloatingRail() {
        railOverlayRequested = false
    }

    mutating func didDockRail() {
        // Growing the window consumes the temporary popup request. Shrinking again
        // hides the rail until another explicit click, rather than reopening a popup.
        railOverlayRequested = false
        railPreservesSidebar = false
    }

    mutating func resizePanel(to width: CGFloat) {
        guard let panel else { return }
        widths[panel] = min(panel.maximumWidth, max(panel.minimumWidth, width))
    }

    func project(width: CGFloat, supportsInspector: Bool) -> Projection {
        let width = max(0, width)
        let activePanel = supportsInspector ? panel : nil
        let rail = activePanel == .sessionRail
        let focused = activePanel != nil && !rail && isFocused
        let minimum = activePanel?.minimumWidth ?? 0
        let canDock: Bool
        if rail {
            let preservedSidebar = railPreservesSidebar && sidebarPreferred ? sidebarWidth + 1 : 0
            canDock = width >= preservedSidebar + Self.mainMinimum + minimum + 1
        } else {
            canDock = activePanel != nil && width >= Self.compactMainMinimum + Self.compactToolMinimum + 1
        }
        let floating = rail && !canDock && railOverlayRequested
        let presentation: Presentation = focused ? .focused : (canDock ? .docked : (floating ? .floatingRail : .hidden))
        // Inline tools can use a compact split after the sidebar has collapsed.
        // A floating rail never takes space away from either existing column.
        let minimumBody = focused ? minimum : Self.mainMinimum + (canDock ? minimum + 1 : 0)
        let sidebar = sidebarPreferred && width >= sidebarWidth + 1 + minimumBody ? sidebarWidth : 0
        let available = max(0, width - (sidebar > 0 ? sidebar + 1 : 0))
        let panelWidth: CGFloat
        if let activePanel {
            let preferred = widths[activePanel] ?? activePanel.defaultWidth
            switch presentation {
            case .focused: panelWidth = available
            case .floatingRail: panelWidth = min(preferred, max(0, available - 24))
            case .docked:
                let mainMinimum = rail ? Self.mainMinimum : min(
                    Self.mainMinimum,
                    max(Self.compactMainMinimum, available - activePanel.minimumWidth - 1)
                )
                panelWidth = min(preferred, max(0, available - mainMinimum - 1))
            case .hidden: panelWidth = 0
            }
        } else {
            panelWidth = 0
        }
        let mainWidth = focused ? 0 : (presentation == .docked ? max(0, available - panelWidth - 1) : available)
        return Projection(windowWidth: width, sidebarWidth: sidebar, panelWidth: panelWidth,
                          mainWidth: mainWidth, presentation: presentation, activePanel: activePanel)
    }
}

import XCTest
@testable import Talkify

final class MacWorkspaceLayoutTests: XCTestCase {
    func testConversationDefaultsToRailAndOtherPagesHideIt() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        XCTAssertEqual(layout.panel, .sessionRail)
        let wide = layout.project(width: 1440, supportsInspector: true)
        XCTAssertTrue(wide.showsSidebar)
        XCTAssertEqual(wide.panelWidth, 320)
        layout.selectPage(isConversation: false)
        XCTAssertNil(layout.panel)
    }

    func testSidebarCollapsesBeforeRailAndWindowGrowthRestoresBoth() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        let narrow = layout.project(width: 900, supportsInspector: true)
        XCTAssertFalse(narrow.showsSidebar)
        XCTAssertEqual(narrow.panelWidth, 320)
        let tiny = layout.project(width: 700, supportsInspector: true)
        XCTAssertFalse(tiny.showsPanel)
        XCTAssertEqual(layout.panel, .sessionRail)
        let restored = layout.project(width: 1440, supportsInspector: true)
        XCTAssertTrue(restored.showsSidebar)
        XCTAssertTrue(restored.showsPanel)
    }

    func testManualClosePersistsAcrossResizeUntilAnotherConversation() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        layout.closePanel()
        XCTAssertFalse(layout.project(width: 700, supportsInspector: true).showsPanel)
        XCTAssertFalse(layout.project(width: 1440, supportsInspector: true).showsPanel)
        layout.selectPage(isConversation: true)
        XCTAssertEqual(layout.panel, .sessionRail)
    }

    func testFileNavigationReusesWidthNeverTogglesAndOnlyExplicitExpandFocuses() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        layout.open(.files, availableWidth: 1440)
        layout.resizePanel(to: 580)
        layout.isFocused = true
        layout.showTool(.files)
        XCTAssertEqual(layout.panel, .files)
        XCTAssertFalse(layout.isFocused)
        XCTAssertEqual(layout.widths[.files], 580)
        layout.showTool(.files)
        XCTAssertEqual(layout.panel, .files)
        layout.closePanel()
        XCTAssertEqual(layout.panel, .sessionRail)
    }

    func testOpeningFileFromTransientDetailDoesNotRestoreEmptyDetailWhenClosed() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        layout.panelBeforeTool = .sessionRail
        layout.panel = .detail
        layout.showTool(.files)
        layout.closePanel()
        XCTAssertEqual(layout.panel, .sessionRail)
    }

    func testToolsRestoreRailAndRememberSeparateWidths() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        layout.open(.terminal, availableWidth: 1440)
        layout.resizePanel(to: 640)
        layout.open(.files, availableWidth: 1440)
        layout.resizePanel(to: 480)
        layout.closePanel()
        XCTAssertEqual(layout.panel, .sessionRail)
        layout.open(.terminal, availableWidth: 1440)
        XCTAssertEqual(layout.project(width: 1600, supportsInspector: true).panelWidth, 640)
        layout.open(.files, availableWidth: 1440)
        XCTAssertEqual(layout.project(width: 1600, supportsInspector: true).panelWidth, 480)
    }

    func testTemporaryClampingDoesNotOverwritePreferredWidth() {
        var layout = MacWorkspaceLayout()
        layout.open(.changes, availableWidth: 1440)
        layout.resizePanel(to: 700)
        XCTAssertEqual(layout.project(width: 900, supportsInspector: true).panelWidth, 459)
        XCTAssertEqual(layout.widths[.changes], 700)
        XCTAssertEqual(layout.project(width: 1600, supportsInspector: true).panelWidth, 700)
    }

    func testOpeningToolsInNarrowWindowPreservesConversation() {
        for panel in [MacWorkspaceLayout.Panel.terminal, .browser, .files, .changes, .detail] {
            var layout = MacWorkspaceLayout()
            layout.selectPage(isConversation: true)
            layout.open(panel, availableWidth: 720)
            let split = layout.project(width: 720, supportsInspector: true)
            XCTAssertEqual(split.presentation, .docked)
            XCTAssertFalse(split.isFocused)
            XCTAssertFalse(split.showsSidebar)
            XCTAssertGreaterThanOrEqual(split.mainWidth, MacWorkspaceLayout.compactMainMinimum)
            XCTAssertGreaterThanOrEqual(split.panelWidth, MacWorkspaceLayout.compactToolMinimum)
            layout.closePanel()
            XCTAssertEqual(layout.panel, .sessionRail)
        }
    }

    func testRailFloatsOnlyAfterExplicitClickWithoutChangingExistingColumns() {
        for sidebarPreferred in [true, false] {
            var layout = MacWorkspaceLayout()
            layout.sidebarPreferred = sidebarPreferred
            layout.selectPage(isConversation: true)
            let before = layout.project(width: 700, supportsInspector: true)
            XCTAssertFalse(before.showsPanel)
            XCTAssertFalse(before.isSelected(.sessionRail))
            layout.open(.sessionRail, availableWidth: 700)
            let floating = layout.project(width: 700, supportsInspector: true)
            XCTAssertTrue(floating.floatsRail)
            XCTAssertTrue(floating.isSelected(.sessionRail))
            XCTAssertEqual(floating.sidebarWidth, before.sidebarWidth)
            XCTAssertEqual(floating.mainWidth, before.mainWidth)
            XCTAssertFalse(floating.isFocused)
            layout.dismissFloatingRail()
            let dismissed = layout.project(width: 700, supportsInspector: true)
            XCTAssertFalse(dismissed.showsPanel)
            XCTAssertFalse(dismissed.isSelected(.sessionRail))
        }
    }

    func testRailPopupDoesNotCollapseAnAlreadyVisibleSidebar() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        layout.closePanel()
        let before = layout.project(width: 900, supportsInspector: true)
        XCTAssertTrue(before.showsSidebar)
        layout.open(.sessionRail, availableWidth: 900)
        let floating = layout.project(width: 900, supportsInspector: true)
        XCTAssertTrue(floating.floatsRail)
        XCTAssertEqual(floating.sidebarWidth, before.sidebarWidth)
        XCTAssertEqual(floating.mainWidth, before.mainWidth)
        layout.dismissFloatingRail()
        let dismissed = layout.project(width: 900, supportsInspector: true)
        XCTAssertFalse(dismissed.showsPanel)
        XCTAssertEqual(dismissed.mainWidth, before.mainWidth)
        let wide = layout.project(width: 1200, supportsInspector: true)
        XCTAssertEqual(wide.presentation, .docked)
        XCTAssertTrue(wide.showsSidebar)
    }

    func testFloatingRailDocksOnWindowGrowthAndDoesNotReopenOnShrink() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        layout.open(.sessionRail, availableWidth: 700)
        XCTAssertTrue(layout.project(width: 700, supportsInspector: true).floatsRail)
        let grown = layout.project(width: 1440, supportsInspector: true)
        XCTAssertEqual(grown.presentation, .docked)
        XCTAssertTrue(grown.showsSidebar)
        layout.didDockRail()
        XCTAssertFalse(layout.project(width: 700, supportsInspector: true).showsPanel)
    }

    func testFloatingRailToggleAndToolSwitch() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        layout.open(.sessionRail, availableWidth: 700)
        layout.open(.sessionRail, availableWidth: 700)
        XCTAssertNil(layout.panel)
        layout.open(.sessionRail, availableWidth: 700)
        layout.open(.files, availableWidth: 700)
        let files = layout.project(width: 700, supportsInspector: true)
        XCTAssertFalse(files.floatsRail)
        XCTAssertTrue(files.isSelected(.files))
        XCTAssertFalse(files.isSelected(.sessionRail))
    }

    func testOnlyExplicitExpandCanHideConversation() {
        var layout = MacWorkspaceLayout()
        layout.open(.browser, availableWidth: 700)
        XCTAssertGreaterThan(layout.project(width: 700, supportsInspector: true).mainWidth, 0)
        layout.isFocused = true
        XCTAssertEqual(layout.project(width: 700, supportsInspector: true).mainWidth, 0)
        layout.isFocused = false
        XCTAssertGreaterThan(layout.project(width: 700, supportsInspector: true).mainWidth, 0)
    }

    func testHiddenPanelNeverHasSelectedToolbarEntry() {
        var layout = MacWorkspaceLayout()
        layout.selectPage(isConversation: true)
        XCTAssertFalse(layout.project(width: 700, supportsInspector: true).isSelected(.sessionRail))
        layout.open(.files, availableWidth: 700)
        XCTAssertFalse(layout.project(width: 400, supportsInspector: true).isSelected(.files))
        XCTAssertTrue(layout.project(width: 1440, supportsInspector: true).isSelected(.files))
    }

    func testDashboardNeverProjectsConversationTools() {
        var layout = MacWorkspaceLayout()
        layout.open(.files, availableWidth: 720)
        let dashboard = layout.project(width: 1440, supportsInspector: false)
        XCTAssertFalse(dashboard.showsPanel)
        XCTAssertFalse(dashboard.isFocused)
    }

    func testCompactToolWidthsChangeContinuouslyDuringResize() {
        var layout = MacWorkspaceLayout()
        layout.sidebarPreferred = false
        layout.open(.files, availableWidth: 700)
        var previous = layout.project(width: 521, supportsInspector: true)
        for width in 522...1200 {
            let next = layout.project(width: CGFloat(width), supportsInspector: true)
            XCTAssertLessThanOrEqual(abs(next.mainWidth - previous.mainWidth), 1.01)
            XCTAssertLessThanOrEqual(abs(next.panelWidth - previous.panelWidth), 1.01)
            previous = next
        }
    }

    func testWidthsStayWithinBoundsAndConserveSpace() {
        var layout = MacWorkspaceLayout()
        for panel in MacWorkspaceLayout.Panel.allCases {
            layout.panel = panel
            layout.resizePanel(to: 2000)
            XCTAssertEqual(layout.widths[panel], panel.maximumWidth)
            layout.resizePanel(to: 10)
            XCTAssertEqual(layout.widths[panel], panel.minimumWidth)
            for width in stride(from: CGFloat(320), through: 1800, by: 20) {
                let projected = layout.project(width: width, supportsInspector: true)
                let occupied = projected.sidebarWidth + (projected.showsSidebar ? 1 : 0)
                    + projected.panelWidth + (projected.showsPanel ? 1 : 0)
                XCTAssertLessThanOrEqual(occupied, width)
                if projected.showsPanel {
                    let mainMinimum = panel == .sessionRail ? MacWorkspaceLayout.mainMinimum : MacWorkspaceLayout.compactMainMinimum
                    let toolMinimum = panel == .sessionRail ? panel.minimumWidth : MacWorkspaceLayout.compactToolMinimum
                    XCTAssertGreaterThanOrEqual(width - occupied, mainMinimum)
                    XCTAssertGreaterThanOrEqual(projected.panelWidth, toolMinimum)
                }
            }
        }
    }
}

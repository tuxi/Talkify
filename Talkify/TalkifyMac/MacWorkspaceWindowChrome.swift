#if os(macOS)
import AppKit
import SwiftUI

/// Only empty header space drags the window; buttons retain their normal hit testing.
struct MacWorkspaceHeaderDragArea: NSViewRepresentable {
    var onMouseDown: () -> Void = {}

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onMouseDown = onMouseDown
        return view
    }
    func updateNSView(_ nsView: DragView, context: Context) { nsView.onMouseDown = onMouseDown }

    final class DragView: NSView {
        var onMouseDown: (() -> Void)?
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            onMouseDown?()
            window?.performDrag(with: event)
        }
    }
}
#endif

#if os(macOS)
/// A transient rail dismisses on outside clicks or scrolling, without reacting to hover.
struct MacWorkspaceOutsideInteractionDismissal: NSViewRepresentable {
    let dismiss: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.dismiss = dismiss
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) { nsView.dismiss = dismiss }

    final class MonitorView: NSView {
        var dismiss: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                // Header controls own their toggles. Dismissing before the rail button's
                // action would turn its close click into a new open request.
                let rectInWindow = self.convert(self.bounds, to: nil)
                if event.locationInWindow.y > rectInWindow.maxY { return event }
                if !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.dismiss?()
                }
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
#endif

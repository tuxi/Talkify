//
//  AppMenu.swift
//  CodeAgent
//

#if os(macOS)
import AppKit
import SwiftUI

/// A reusable, rich-content menu backed by a transient `NSPopover`.
/// Unlike SwiftUI `Menu`, the label and menu content are independent and the
/// content can contain controls, disclosure sections, and custom layout.
enum AppMenuPresentation {
    /// Shows next to the pointer location inside the trigger view.
    case pointer
    /// Uses the complete trigger view as a stable anchor.
    case fixedToTrigger(preferredEdge: NSRectEdge)
    /// Shows at a caller-provided rect in the trigger view's coordinate space.
    case fixed(rect: CGRect, preferredEdge: NSRectEdge)
}

struct AppMenu<Label: View, Content: View>: NSViewRepresentable {
    let presentation: AppMenuPresentation
    private let label: () -> Label
    private let content: (@escaping (CGSize) -> Void) -> Content

    init(
        presentation: AppMenuPresentation = .pointer,
        @ViewBuilder content: @escaping (@escaping (CGSize) -> Void) -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.presentation = presentation
        self.label = label
        self.content = content
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSHostingView<Label> {
        let view = NSHostingView(rootView: label())
        let recognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        recognizer.buttonMask = 0x1
        view.addGestureRecognizer(recognizer)
        context.coordinator.hostView = view
        context.coordinator.presentation = presentation
        context.coordinator.content = { resize in AnyView(content(resize)) }
        return view
    }

    func updateNSView(_ nsView: NSHostingView<Label>, context: Context) {
        nsView.rootView = label()
        context.coordinator.hostView = nsView
        context.coordinator.presentation = presentation
        context.coordinator.content = { resize in AnyView(content(resize)) }
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        weak var hostView: NSView?
        var presentation: AppMenuPresentation = .pointer
        var content: ((@escaping (CGSize) -> Void) -> AnyView)?
        private var popover: NSPopover?

        @objc func showMenu(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended,
                  let hostView,
                  let content else { return }

            popover?.performClose(nil)

            let controller = NSHostingController(rootView: content { [weak self] size in
                self?.resizePopover(to: size)
            })
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.contentViewController = controller
            popover.delegate = self
            self.popover = popover

            let anchor: CGRect
            let edge: NSRectEdge
            switch presentation {
            case .pointer:
                let point = recognizer.location(in: hostView)
                anchor = CGRect(x: point.x, y: point.y, width: 1, height: 1)
                edge = .maxY
            case let .fixedToTrigger(preferredEdge):
                // Anchor at the trigger's bottom-center, rather than using its
                // full bounds. NSHostingView can be taller than the visual
                // label, while this point remains stable at the footer edge.
                anchor = CGRect(
                    x: hostView.bounds.midX,
                    y: hostView.bounds.minY,
                    width: 1,
                    height: 1
                )
                edge = preferredEdge
            case let .fixed(rect, preferredEdge):
                anchor = rect
                edge = preferredEdge
            }

            popover.show(relativeTo: anchor, of: hostView, preferredEdge: edge)
        }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
        }

        private func resizePopover(to size: CGSize) {
            guard let popover else { return }
            popover.contentSize = NSSize(width: size.width, height: size.height)
        }
    }
}
#endif

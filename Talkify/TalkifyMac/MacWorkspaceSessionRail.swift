#if os(macOS)
import SwiftUI

/// A reusable session surface, independent of whether it is docked or floating.
/// Its conversation state belongs to the host, not the presentation container.
struct MacWorkspaceSessionRail<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Session rail")
    }
}
#endif

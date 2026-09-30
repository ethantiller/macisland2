import SwiftUI

/// Surfaces that float free of the notch: the command palette, menu-bar modules, torn-off panels.
/// Never used on the island itself.
struct FloatingGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Metrics.floatPadding)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.Metrics.floatRadius))
    }
}

extension View {
    func floatingGlass() -> some View {
        modifier(FloatingGlass())
    }
}

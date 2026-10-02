import SwiftUI

/// Surfaces that float free of the notch: menu-bar modules and torn-off panels.
/// Never used on the island itself.
struct FloatingGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Metrics.floatPadding)
            .glassSurface(in: .rect(cornerRadius: Theme.Metrics.floatRadius))
    }
}

extension View {
    func floatingGlass() -> some View {
        modifier(FloatingGlass())
    }
}

extension View {
    /// Liquid Glass on macOS 26; on macOS 15, which has none, the regular material in the same shape.
    @ViewBuilder
    func glassSurface(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

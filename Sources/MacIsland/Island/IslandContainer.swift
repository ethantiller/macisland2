import SwiftUI

/// What the island is showing, smallest to largest.
enum IslandPresentation: Equatable {
    /// Beside the notch: one live activity split around the camera.
    case compact
    /// A momentary announcement below the notch.
    case banner
    /// The pointer rests on the island: the top activity at full size, without tabs.
    case peek
    /// Click, swipe down, or the shortcut: the tab strip and the selected module.
    case expanded

    /// Everything but compact hangs below the notch and takes the large corner radius.
    var hangsBelowNotch: Bool { self != .compact }
}

/// What the island is drawn on.
enum IslandSurface: Equatable {
    /// Pure black, continuous with the hardware notch.
    case hardware
    /// Dark regular Liquid Glass, on displays without a notch where there's no hardware to match.
    case glass
}

/// The island's outline, surface, size, and motion. `IslandView` supplies what goes inside.
struct IslandContainer<Content: View>: View {
    let presentation: IslandPresentation
    let size: CGSize
    let surface: IslandSurface
    /// The pointer is resting on the compact island; it swells slightly until the peek opens.
    let isSwelling: Bool
    var horizontalOffset: CGFloat = 0
    @ViewBuilder let content: Content

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = NotchShape(
            topFlare: ScreenGeometry.topFlare,
            bottomRadius: presentation.hangsBelowNotch ? Theme.Metrics.expandedRadius : Theme.Metrics.compactRadius
        )
        let swell = isSwelling && !reduceMotion ? Theme.Metrics.swell : .zero

        content
            .frame(
                width: pixelAligned(size.width + swell.width),
                height: pixelAligned(size.height + swell.height),
                alignment: .top
            )
            .modifier(IslandSurfaceStyle(surface: surface, shape: shape))
            .contentShape(shape)
            .offset(x: horizontalOffset)
            .environment(\.colorScheme, .dark)
            .environment(\.islandSurface, surface)
    }

    /// Rounds to the display's pixel grid so the island's edges stay crisp against the bezel.
    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        (value * displayScale).rounded() / displayScale
    }
}

/// Black against the hardware notch; Liquid Glass only where there is no notch to match.
struct IslandSurfaceStyle<S: Shape>: ViewModifier {
    let surface: IslandSurface
    let shape: S

    func body(content: Content) -> some View {
        switch surface {
        case .hardware:
            content
                .background(Theme.Palette.surface, in: shape)
                .clipShape(shape)
        case .glass:
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        }
    }
}

import AppKit

struct ScreenGeometry: Equatable {
    static let panelSize = CGSize(width: 560, height: 260)
    /// Width of the outward flare at each top corner of the island shape.
    static let topFlare: CGFloat = 6

    var screenFrame: CGRect
    var notchSize: CGSize
    var hasNotch: Bool

    /// Island size when collapsed: covers the notch exactly, plus the flares.
    var compactSize: CGSize {
        CGSize(width: notchSize.width + Self.topFlare * 2, height: notchSize.height)
    }

    var panelFrame: CGRect {
        CGRect(
            x: screenFrame.midX - Self.panelSize.width / 2,
            y: screenFrame.maxY - Self.panelSize.height,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )
    }

    /// Screen-coordinate rect of an island of the given size, hanging from the top edge.
    func islandRect(for size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            // Extend past the top edge so the very top pixel row still counts as inside.
            height: size.height + 2
        )
    }

    static func current() -> ScreenGeometry {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notched ?? NSScreen.main ?? NSScreen.screens.first else {
            return ScreenGeometry(screenFrame: .zero, notchSize: CGSize(width: 200, height: 32), hasNotch: false)
        }

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return ScreenGeometry(
                screenFrame: screen.frame,
                notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                hasNotch: true
            )
        }

        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return ScreenGeometry(
            screenFrame: screen.frame,
            notchSize: CGSize(width: 200, height: menuBarHeight),
            hasNotch: false
        )
    }
}

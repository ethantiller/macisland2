import AppKit

struct ScreenGeometry: Equatable {
    static let panelSize = CGSize(width: 560, height: Theme.Metrics.panelHeight)
    static var hostingPanelWidth: CGFloat {
        panelSize.width + 2 * (Theme.Metrics.outputSatelliteGap + Theme.Metrics.outputPillMaxWidth)
    }
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
        let width = Self.hostingPanelWidth
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - Self.panelSize.height,
            width: width,
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

    /// What choosing a display needs to know about one.
    struct Traits: Equatable {
        var hasNotch: Bool
        var isBuiltIn: Bool
    }

    /// Which screen carries the island. `screens` is in the system's order, whose first is the primary display (the one with
    /// the menu bar). Built-in: the notched display, else any built-in display, else the one in use (`mainIndex`).
    /// Primary: the first. Nil when there are no screens.
    static func choose(_ screens: [Traits], preference: IslandDisplay, mainIndex: Int = 0) -> Int? {
        guard !screens.isEmpty else { return nil }
        switch preference {
        case .primary: return 0
        case .builtIn:
            return screens.firstIndex { $0.hasNotch } ?? screens.firstIndex { $0.isBuiltIn }
                ?? (screens.indices.contains(mainIndex) ? mainIndex : 0)
        }
    }

    private static func traits(of screen: NSScreen) -> Traits {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return Traits(
            hasNotch: screen.safeAreaInsets.top > 0,
            isBuiltIn: number.map { CGDisplayIsBuiltin(CGDirectDisplayID($0.uint32Value)) != 0 } ?? false)
    }

    static func current(display: IslandDisplay = .builtIn) -> ScreenGeometry {
        let screens = NSScreen.screens
        let main = NSScreen.main.flatMap { screens.firstIndex(of: $0) } ?? 0
        let chosen = choose(screens.map(traits(of:)), preference: display, mainIndex: main).map { screens[$0] }
        guard let screen = chosen else {
            return ScreenGeometry(screenFrame: .zero, notchSize: CGSize(width: 200, height: 32), hasNotch: false)
        }

        if screen.safeAreaInsets.top > 0,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        {
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

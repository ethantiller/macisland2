import AppKit
import SwiftUI

/// The island's design tokens. Views use these instead of literal colors, fonts, or sizes.
/// Rules and rationale live in DESIGN.md.
enum Theme {
    /// Ink and fills that follow the surface they are on. On the island (pure black) they are white at set
    /// opacities. On floating glass they are the system's primary color at the same opacities, so the same views
    /// read correctly in light and dark. The surface is set with `\.islandSurface`.
    enum Palette {
        /// Pure black so the island is indistinguishable from the notch.
        static let surface = Color.black
        static let primary = SurfaceInk(opacity: 1)
        static let secondary = SurfaceInk(opacity: 0.6)
        /// Glyphs only (≈3.4:1); never use for text.
        static let tertiary = SurfaceInk(opacity: 0.38)
        static let fill = SurfaceInk(opacity: 0.12)
        static let fillHover = SurfaceInk(opacity: 0.2)
        /// A widget's box on Home: darker than a control's fill, so blocks are told apart without standing out.
        static let widget = SurfaceInk(opacity: 0.06)
        /// The hairline around a widget's box.
        static let widgetEdge = SurfaceInk(opacity: 0.07)
        /// What sits on a `primary` fill: black on the island, the window's own color on glass.
        static let inverse = SurfaceInk(role: .inverse)
        /// Nothing: for the "off" side of a ternary that would otherwise be `.clear`.
        static let none = SurfaceInk(opacity: 0)
    }

    /// Color means something is live, and each color means one thing. See DESIGN.md.
    enum Tint {
        /// Time: timer, stopwatch, Pomodoro.
        static let clock = Color.orange
        /// In progress: downloads, agent turns, shell commands, zipping and converting.
        static let working = Color.blue
        /// Done or connected: charging, saved, unlocked, connected.
        static let positive = Color.green
        /// Needs you: an approval, low battery, a missing permission.
        static let attention = Color.red
        static let neutral = Color.white
    }

    enum Typography {
        static let title = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 12)
        static let bodyEmphasized = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 10, weight: .medium)
        static let numeral = Font.system(size: 10, weight: .medium, design: .rounded).monospacedDigit()
        static let compactNumeral = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
        static let largeNumeral = Font.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()
        static let glyph = Font.system(size: 13, weight: .medium)
        /// The music player, after the Dynamic Island's: the song, and who plays it.
        static let headline = Font.system(size: 15, weight: .semibold)
        static let subheadline = Font.system(size: 13, weight: .regular)
        /// The command palette's field: the one thing on it you look at while typing.
        static let query = Font.system(size: 20, weight: .regular)
        /// The Prompter: readable from arm's length while looking at the camera.
        static let prompter = Font.system(size: 20, weight: .medium)
    }

    enum Metrics {
        /// Fits `maxTabs` glyphs left of the notch, and `maxRightTabs` right of it with the status and Settings.
        static let expandedWidth: CGFloat = 520
        /// Peek and banner share a width, so one becomes the other by changing height only.
        static let peekWidth: CGFloat = 380
        static let bannerWidth: CGFloat = peekWidth
        static let maxTabs = 5
        /// The tab right of the notch, beside the status and the gear.
        static let maxRightTabs = 1
        /// Side margin inside the expanded island, measured from the visible edge.
        static let margin: CGFloat = 18
        static let contentTopGap: CGFloat = 8
        static let expandedRadius: CGFloat = 32
        static let compactRadius: CGFloat = 10
        /// Radius for containers near the bottom corners, concentric with the island.
        static let innerRadius: CGFloat = expandedRadius - margin
        /// The compact island grows by this while the pointer rests on it, before the peek opens.
        static let swell = CGSize(width: 8, height: 2)
        /// Square that every standalone glyph sits in, so symbols of different widths share a center.
        static let glyphSlot: CGFloat = 20
        static let rowSpacing: CGFloat = 8
        /// Minimum hit target for any control (HIG macOS minimum is 20pt).
        static let hitTarget: CGFloat = 28
        static let sliderHitHeight: CGFloat = 20
        /// Banner height below the notch.
        static let bannerContentHeight: CGFloat = 56
        /// While a file is dragged, the compact island grows by this much on each side and below.
        static let dragTargetInset: CGFloat = 90
        static let dragTargetHeight: CGFloat = 48
        static let artwork: CGFloat = 40
        /// The player's album art in the Media tab, and in the peek (which is narrower).
        static let playerArtwork: CGFloat = 58
        static let playerPeekArtwork: CGFloat = 50
        /// The Media tab starts a little lower than other tabs, so the art has room to breathe.
        static let playerTopInset: CGFloat = 4
        /// The big transport buttons' hit area, and the scrubber row.
        static let playerTransport: CGFloat = 34
        /// Space between the player's rows.
        static let playerSpacing: CGFloat = 6
        static let playerScrubber: CGFloat = 20
        /// Timer and stopwatch ring; its height sets the Clock tab's height.
        static let clockRing: CGFloat = 64
        static let artworkRadius: CGFloat = 8
        static let cardRadius: CGFloat = 10
        /// Home's widgets, concentric with the island: its 32 radius less its 18 margin. Continuous.
        static let widgetRadius: CGFloat = innerRadius
        /// What sits inside a widget: artwork, a hovered segment.
        static let nestedRadius: CGFloat = artworkRadius
        static let clipboardCardWidth: CGFloat = 108
        static let shelfChoiceWidth: CGFloat = 150
        /// The Shelf: a Files or Clipboard choice, and cards tall enough for a smart action.
        static let shelfHeight: CGFloat = 96
        /// Notes: the mode picker, then a list and editor (or the prompter and its controls).
        static let notesHeight: CGFloat = 28 + 8 + 112
        /// Reminders: the add field, then four rows of the list.
        static let remindersHeight: CGFloat = 28 + 8 + 4 * 30
        static let toolsRowHeight: CGFloat = 54
        /// Two rows of four.
        static let toolsGridHeight: CGFloat = 2 * toolsRowHeight + 10
        static let ringLightControlsHeight: CGFloat = 30
        /// The Keep Awake duration chips, and the gap above them.
        /// Pomodoro's streak line and 7-day chart under the ring, and the gap above them.
        static let pomodoroStatsHeight: CGFloat = 58
        static let keepAwakeChipsHeight: CGFloat = hitTarget + 10
        /// The device battery strip under the agenda in Home.
        /// Height of a one-row module: Now Playing, the agenda, and the peek.
        static let glanceHeight: CGFloat = 68
        /// The current lyric line under the scrubber, and the gap above it.
        static let lyricsRowHeight: CGFloat = 24
        /// Home's rows: the time and music widgets, then the actions.
        static let homeCardHeight: CGFloat = 64
        static let homeActionsHeight: CGFloat = 68
        /// The four quick tools' round buttons in Home's 2 by 2 grid, and the buttons in the idle peek.
        static let homeGridButton: CGFloat = 24
        static let homeQuickHeight: CGFloat = 32
        static let homeHeaderHeight: CGFloat = 28
        /// Home with the month calendar open: the header and six weeks.
        static let homeMonthHeight: CGFloat = 170
        /// Home closed: the two rows, with 10 pt between them.
        static let homeContentHeight: CGFloat = 64 + 68 + 10
        /// The idle peek: the date, weather and what is next, then the quick controls.
        static let idlePeekHeight: CGFloat = 44 + 10 + 32
        /// Floating glass: command palette, menu-bar modules, torn-off panels.
        static let floatRadius: CGFloat = 24
        /// Inset inside floating glass; `floatRadius - floatPadding == cardRadius`, so corners are concentric.
        static let floatPadding: CGFloat = 14
        /// Gap between the notch and floating glass hung below it.
        static let floatGap: CGFloat = 8
        /// The command palette, including its glass padding.
        static let paletteWidth: CGFloat = 520
        /// A torn-off module: its content width, and the header above the content.
        static let detachedWidth: CGFloat = 472
        static let detachedHeaderHeight: CGFloat = 28
        static let detachedChromeHeight: CGFloat = 28 + rowSpacing
    }

    enum Timing {
        /// Pointer rest before the peek opens. The swell answers at once, so this can stay short.
        static let peekDwell: Duration = .milliseconds(120)
        /// Pointer gone before the island folds back in.
        static let closeDelay: Duration = .milliseconds(300)
    }

    enum Motion {
        static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

        /// Out of the notch: compact to peek or expanded, and alerts or banners arriving.
        /// One small settle (bounce 0.22), like the Dynamic Island.
        static var open: Animation {
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.78)
        }

        /// Back into the notch. Critically damped: an overshoot would pull the island inside the hardware.
        static var close: Animation {
            reduceMotion ? .easeIn(duration: 0.16) : .spring(response: 0.34, dampingFraction: 1)
        }

        /// Size changes inside an open island: tabs, modes, heights. Nearly critical, since it repeats often.
        static var resize: Animation {
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.88)
        }

        /// Follows the pointer: the hover swell, swipes, the drag target. Retargets mid-flight without a jump.
        static var track: Animation {
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.1)
        }

        /// Floating glass (palette, torn-off panels) dropping in below the notch.
        static var float: Animation {
            reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.84)
        }

        /// Content changing while the island changes shape.
        static var content: AnyTransition {
            reduceMotion ? .opacity : .modifier(active: BlurFade(amount: 1), identity: BlurFade(amount: 0))
        }

        /// Floating glass appearing from the notch above it.
        static var floatTransition: AnyTransition {
            reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
        }
    }
}

/// The Dynamic Island's content change: outgoing content blurs away while the next sharpens in.
struct BlurFade: ViewModifier {
    /// 0 is fully shown, 1 is fully gone.
    var amount: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 8 * amount)
            .opacity(1 - amount)
            .scaleEffect(1 - 0.06 * amount, anchor: .top)
    }
}

/// What the palette is drawn on.
private struct IslandSurfaceKey: EnvironmentKey {
    static let defaultValue: IslandSurface = .hardware
}

extension EnvironmentValues {
    var islandSurface: IslandSurface {
        get { self[IslandSurfaceKey.self] }
        set { self[IslandSurfaceKey.self] = newValue }
    }
}

/// `Theme.Palette`'s ink: white on the island, the system's primary color on glass, at one opacity. `inverse`
/// is the content color on a `primary` fill (a selected chip, an "on" button): black on the island, the
/// window's own color on glass. One type, so a ternary can pick between them.
struct SurfaceInk: ShapeStyle {
    enum Role { case ink(Double), inverse }

    let role: Role

    init(opacity: Double) { role = .ink(opacity) }
    init(role: Role) { self.role = role }

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        let onGlass = environment.islandSurface == .glass
        switch role {
        case .ink(let opacity):
            return (onGlass ? Color.primary : Color.white).opacity(opacity)
        case .inverse:
            return onGlass ? Color(nsColor: .windowBackgroundColor) : Color.black
        }
    }
}

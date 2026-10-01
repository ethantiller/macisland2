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
        /// Almost nothing, and not nothing. A window with a clear background passes clicks through its clear pixels, so a floating window
        /// with controls on glass lays this under the glass to be clickable and draggable everywhere on it. Too faint to see.
        static let hitSurface = Color.black.opacity(0.02)
        /// What sits on a `primary` fill: black on the island, the window's own color on glass.
        static let inverse = SurfaceInk(role: .inverse)
        /// Nothing: for the "off" side of a ternary that would otherwise be `.clear`.
        static let none = SurfaceInk(opacity: 0)
        /// The Agents activity map: no use, then four steps of white up to full.
        static let activitySteps = [
            SurfaceInk(opacity: 0.12), SurfaceInk(opacity: 0.3), SurfaceInk(opacity: 0.55), SurfaceInk(opacity: 0.8),
            SurfaceInk(opacity: 1),
        ]
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
        /// AirDrop's own blue, for the AirDrop drop target only, so it reads as AirDrop and not as storage.
        static let airDrop = Color(red: 0.16, green: 0.62, blue: 1.0)
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
        /// The Prompter: readable from arm's length while looking at the camera.
        static let prompter = Font.system(size: 20, weight: .medium)
    }

    enum Metrics {
        /// Fits `maxTabs` glyphs left of the notch, and `maxRightTabs` right of it with the status and Settings.
        static let expandedWidth: CGFloat = 520
        /// Peek and banner share a width, so one becomes the other by changing height only.
        static let peekWidth: CGFloat = 380
        static let bannerWidth: CGFloat = peekWidth
        /// A banner with nothing to press (AirPods, low battery, rain) is an alert: a smaller island, its contents centered.
        static let bannerAlertWidth: CGFloat = 290
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
        static let dragTargetInset: CGFloat = 100
        static let dragTargetHeight: CGFloat = 56
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
        /// The minute ruler shown while a timer is being set: labels, ticks, and the marker.
        static let dialLabelHeight: CGFloat = 12
        static let dialRowSpacing: CGFloat = 3
        static let dialTickWidth: CGFloat = 2
        static let dialMajorTick: CGFloat = 22
        static let dialMinorTick: CGFloat = 14
        /// The fixed triangle under the chosen minute.
        static let dialMarker: CGFloat = 8
        /// Points between two minutes. Also the drag and scroll points per minute, so the ruler follows the pointer 1:1.
        static let dialMinuteSpacing: CGFloat = 8
        /// How far the ruler may stretch past its ends.
        static let dialRubberBand: CGFloat = 24
        /// The ruler fades out over this fraction of its width at each side.
        static let dialFade: CGFloat = 0.16
        static let timerDial: CGFloat = dialLabelHeight + dialRowSpacing + dialMajorTick + dialRowSpacing + dialMarker
        /// The Prompter's text fades over this fraction of its height at each end.
        static let prompterFade: CGFloat = 0.12
        /// Setting a timer: the mode picker and presets.
        static let clockHeaderHeight: CGFloat = 24
        /// Setting a timer: the mode picker and presets, the dial, then Start Timer and the length.
        static let timerSetter: CGFloat = clockHeaderHeight + 10 + timerDial + 10 + hitTarget
        static let artworkRadius: CGFloat = 8
        static let cardRadius: CGFloat = 10
        /// Home's widgets, concentric with the island: its 32 radius less its 18 margin. Continuous.
        static let widgetRadius: CGFloat = innerRadius
        /// What sits inside a widget: artwork, a hovered segment.
        static let nestedRadius: CGFloat = artworkRadius
        /// The volume HUD: a narrow side for the speaker glyph, a long one for the level bar and the percent.
        static let volumeHUDLeading: CGFloat = 44
        static let volumeHUDTrailing: CGFloat = 140
        static let levelBarWidth: CGFloat = 80
        static let levelBarHeight: CGFloat = 4
        static let clipboardCardWidth: CGFloat = 108
        static let shelfChoiceWidth: CGFloat = 150
        /// The Shelf: a Files or Clipboard choice, and cards tall enough for a smart action.
        static let shelfHeight: CGFloat = 96
        /// A file's preview on the Shelf: as large as the row allows under the header, with its name below.
        static let shelfThumbnail: CGFloat = 42
        /// The ✕ that takes a file off the Shelf: its disc, and the larger area that takes the click.
        static let shelfRemove: CGFloat = 16
        static let shelfRemoveHit: CGFloat = 24
        /// Notes: the mode picker, then a list and editor (or the prompter and its controls).
        static let notesHeight: CGFloat = 28 + 8 + 112
        /// Reminders: the add field, then four rows of the list.
        static let remindersHeight: CGFloat = 28 + 8 + 4 * 30
        static let toolsRowHeight: CGFloat = 54
        /// Two rows of six.
        static let toolsGridHeight: CGFloat = 2 * toolsRowHeight + 10
        static let ringLightControlsHeight: CGFloat = 30
        /// The Mirror: a 16:9 preview, and the width that gives it.
        static let mirrorHeight: CGFloat = 180
        static let mirrorWidth: CGFloat = 320
        /// The Keep Awake duration chips, and the gap above them.
        /// Pomodoro's streak line and 7-day chart under the ring, and the gap above them.
        static let pomodoroStatsHeight: CGFloat = 58
        static let keepAwakeChipsHeight: CGFloat = hitTarget + 10
        /// The device battery strip under the agenda in Home.
        /// Height of a one-row module: Now Playing, the agenda, and the peek.
        static let glanceHeight: CGFloat = 68
        /// The current lyric line under the scrubber, and the gap above it.
        static let lyricsRowHeight: CGFloat = 24
        /// The four quick tools' round buttons in Home's 2 by 2 grid, and the buttons in the idle peek.
        static let homeGridButton: CGFloat = 24
        static let homeQuickHeight: CGFloat = 32
        static let homeHeaderHeight: CGFloat = 28
        /// Home with the month calendar open: the header and six weeks.
        static let homeMonthHeight: CGFloat = 170
        /// Home closed with its default two rows, with 10 pt between them.
        static let homeContentHeight: CGFloat = 2 * homeRowHeight + homeRowGap
        /// Home is a grid of widgets in rows: this wide (the island's content, and the torn-off window's), with
        /// `rowSpacing` between widgets and `homeRowGap` between rows.
        static let homeContentWidth: CGFloat = expandedWidth - 2 * (ScreenGeometry.topFlare + margin)
        static let homeRowGap: CGFloat = 10
        /// Home's grid: 6 columns of 72 with `rowSpacing` between (80 n - 8 wide), and 1 to `homeMaxRows` rows of
        /// `homeRowHeight` with `homeRowGap` between (74 m - 10 tall).
        static let homeColumns = 6
        static let homeColumnWidth: CGFloat =
            (homeContentWidth - CGFloat(homeColumns - 1) * rowSpacing) / CGFloat(homeColumns)
        static let homeRowHeight: CGFloat = 64
        static let homeMaxRows = 3
        /// The tallest notch on any Mac, so a layout that fits here fits everywhere.
        static let maxNotchHeight: CGFloat = 38
        /// What Home can be tall: `homeMaxRows` rows, which the panel is built around.
        static let homeMaxContentHeight: CGFloat =
            CGFloat(homeMaxRows) * homeRowHeight + CGFloat(homeMaxRows - 1) * homeRowGap
        /// The panel's height: the worst-case notch, the gap above the content, the tallest Home, and the margin.
        static let panelHeight: CGFloat = maxNotchHeight + contentTopGap + homeMaxContentHeight + margin
        /// The idle peek: the date, weather and what is next, then the quick controls.
        static let idlePeekHeight: CGFloat = 44 + 10 + 32
        /// Floating glass: menu-bar modules and torn-off panels.
        static let floatRadius: CGFloat = 24
        /// Inset inside floating glass; `floatRadius - floatPadding == cardRadius`, so corners are concentric.
        static let floatPadding: CGFloat = 14
        /// Gap between the notch and floating glass hung below it.
        static let floatGap: CGFloat = 8
        /// A torn-off module: its content width, and the header above the content.
        static let detachedWidth: CGFloat = 472
        static let detachedHeaderHeight: CGFloat = 28
        static let detachedChromeHeight: CGFloat = 28 + rowSpacing
        /// Settings chrome for the Home editor, drawn over the preview and never on the island: the remove badge's disc, and the
        /// hit size of the badge and the resize handle.
        static let editorBadge: CGFloat = 18
        static let editorHandle: CGFloat = 28
        /// The band of desk the Settings preview and the first-run guide's stage draw the island on: tall enough for the largest
        /// thing the island draws there (the panel) and a little room under it.
        static let previewBandHeight: CGFloat = panelHeight + 4
        /// The first-run guide: the stage is the 560 pt band at 1:1, inset by the glass's padding on each side.
        static let guideWidth: CGFloat = ScreenGeometry.panelSize.width + 2 * floatPadding
        /// One row of the guide's access step: a 28 pt control and the spacing under it.
        static let guideRowHeight: CGFloat = hitTarget + rowSpacing
        /// The room under the guide's copy. The tallest step detail (three access rows and their two-line note) sets it, and every
        /// step gets that much so the window never changes height: 3 × `guideRowHeight` (108), 8 of spacing, a two-line note (28),
        /// and 6 to spare. Measure it in the app and adjust it with this sum.
        static let guideDetailHeight: CGFloat = 150
        /// The guide's step indicator: a dot, and the wider capsule that marks the current step.
        static let stepDot: CGFloat = 6
        static let stepDotCurrent: CGFloat = 18
        /// A drawn key, a little taller than body text, for naming shortcuts.
        static let keyCapHeight: CGFloat = 22
        static let keyCapRadius: CGFloat = 6
        /// The dot under a day in the month view that has an event.
        static let monthEventDot: CGFloat = 4
        /// The Agents module, in every mode: its header, then what fits under it (two tasks and the limits; the usage; the map).
        static let agentsHeight: CGFloat = 176
        /// The header's two choosers: the modes, and the range of the usage.
        static let agentsModeWidth: CGFloat = 190
        static let agentsRangeWidth: CGFloat = 170
        /// A day in the activity map, and the gap between days. Seven of them, with their gaps, fit under the header.
        static let activityCell: CGFloat = 12
        static let activityGap: CGFloat = 2
        /// The Agents widget's ring, in the 2 by 1 and the 3 by 1.
        static let agentsRing: CGFloat = 36
        /// The Settings tour's callout: wide enough for the longest copy in four lines.
        static let tourCalloutWidth: CGFloat = 280
        /// The callout's arrow, and the space between the ring and the arrow's tip.
        static let tourArrow = CGSize(width: 16, height: 8)
        static let tourGap: CGFloat = 6
        /// The ring around the control the tour points at: how far outside it, and how thick.
        static let tourRingInset: CGFloat = 4
        static let tourRingWidth: CGFloat = 2
        /// The nearest a callout comes to the Settings window's edge.
        static let tourEdgeInset: CGFloat = 12
    }

    enum Timing {
        /// Pointer rest before the peek opens. The swell answers at once, so this can stay short.
        static let peekDwell: Duration = .milliseconds(120)
        /// Pointer gone before the island folds back in.
        static let closeDelay: Duration = .milliseconds(300)
        /// How long the volume HUD stays after the last key press. The pointer on it holds it.
        static let volumeHUD: Duration = .milliseconds(1500)
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

        /// A whole view sliding away for another (Settings' preview between the island and the menu bar). Slower and
        /// nearly critical, so a long slide stays smooth.
        static var slide: Animation {
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.92)
        }

        /// Follows the pointer: the hover swell, swipes, the drag target. Retargets mid-flight without a jump.
        static var track: Animation {
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.1)
        }

        /// How much a widget lifts while the Home editor drags it (Settings chrome only; not with Reduce Motion).
        static let liftScale: CGFloat = 1.03

        /// Floating glass (torn-off panels) dropping in below the notch.
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

/// What Home's and the island's views are drawn on.
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

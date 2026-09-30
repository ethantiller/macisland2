import CoreGraphics

/// The math of the timer dial: a ruler of minutes that slides under a fixed marker. All of it is a pure
/// function of where a gesture started and how far it has moved, so repeated events can't run away.
enum DialScrubber {
    static let minimum = Double(TimerModel.minimumDialMinutes)
    static let maximum = Double(TimerModel.maximumDialMinutes)

    /// Where the ruler sits after a drag of `translation` points from `anchor` minutes. Dragging right pulls
    /// lower minutes under the marker, so the ruler follows the pointer. Not clamped.
    static func position(
        anchor: Double, translation: CGFloat, spacing: CGFloat = Theme.Metrics.dialMinuteSpacing
    ) -> Double {
        anchor - Double(translation / spacing)
    }

    /// A raw position, held to the dial's range, and where the ruler is drawn: past either end it stretches
    /// with resistance, never further than `limit` points.
    struct Resolved: Equatable {
        /// Inside the range: what the timer gets, before rounding.
        var clamped: Double
        /// Where the ruler is drawn.
        var display: Double
        /// How far it is stretched past an end, in points.
        var overscroll: CGFloat
    }

    static func resolve(
        _ raw: Double, spacing: CGFloat = Theme.Metrics.dialMinuteSpacing,
        limit: CGFloat = Theme.Metrics.dialRubberBand
    ) -> Resolved {
        let clamped: Double = min(max(raw, minimum), maximum)
        let overshoot: Double = raw - clamped
        guard overshoot != 0 else { return Resolved(clamped: clamped, display: clamped, overscroll: 0) }
        let stretch: CGFloat = rubberBand(CGFloat(abs(overshoot)) * spacing, limit: limit)
        let display: Double = clamped + (overshoot < 0 ? -1 : 1) * Double(stretch / spacing)
        return Resolved(clamped: clamped, display: display, overscroll: stretch)
    }

    /// Resistance: close to 1:1 at first, then slower, and never past `limit`.
    static func rubberBand(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
        guard distance > 0 else { return 0 }
        return limit * distance / (distance + limit)
    }

    /// The whole minute a position settles on.
    static func snap(_ position: Double) -> Int {
        Int(min(max(position, minimum), maximum).rounded())
    }

    /// The minute whose tick is at `x`, for a ruler whose marker is at `markerX` with `position` under it.
    static func minute(
        atX x: CGFloat, markerX: CGFloat, position: Double, spacing: CGFloat = Theme.Metrics.dialMinuteSpacing
    ) -> Int {
        snap(position + Double((x - markerX) / spacing))
    }

    /// The minutes that fit on a ruler `width` points wide with `position` under its center. Derived, never
    /// stored, so the ruler scrolls and doesn't re-anchor.
    static func visibleRange(
        position: Double, width: CGFloat, spacing: CGFloat = Theme.Metrics.dialMinuteSpacing
    ) -> ClosedRange<Int> {
        let half = Double(width / 2 / spacing)
        let lower = max(Int((position - half).rounded(.up)), TimerModel.minimumDialMinutes)
        let upper = min(Int((position + half).rounded(.down)), TimerModel.maximumDialMinutes)
        return lower...max(lower, upper)
    }
}

/// The first few points of a scroll gesture decide its axis for the whole gesture.
struct AxisLock {
    enum Axis: Equatable { case horizontal, vertical }

    static let threshold: CGFloat = 4

    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private(set) var axis: Axis?

    mutating func reset() {
        x = 0
        y = 0
        axis = nil
    }

    /// Adds finger movement. Returns the horizontal movement so far when this call locks the gesture to
    /// horizontal, so nothing before the lock is lost.
    mutating func add(dx: CGFloat, dy: CGFloat) -> (locked: Axis, horizontalSoFar: CGFloat, justLocked: Bool) {
        if let axis { return (axis, x, false) }
        x += dx
        y += dy
        guard max(abs(x), abs(y)) >= Self.threshold else { return (.vertical, x, false) }
        let locked: Axis = abs(x) > abs(y) ? .horizontal : .vertical
        axis = locked
        return (locked, x, true)
    }
}

/// One scroll event, with the AppKit details a route depends on.
struct ScrollSample {
    var dx: CGFloat
    var dy: CGFloat
    var isPrecise: Bool
    /// Natural scrolling (`isDirectionInvertedFromDevice`).
    var isInverted: Bool
    var isBegan: Bool
    var isMomentum: Bool
}

/// What a scroll event does.
enum ScrollAction: Equatable {
    /// Slide the dial by this much finger movement, in points (right is positive).
    case scrubDial(CGFloat)
    /// A mouse wheel notch over the dial: plus or minus one minute.
    case stepDial(Int)
    /// The usual swipe: open, close, or change tabs.
    case swipe(Swipe)
}

/// Sends each scroll gesture to the dial or to the island. A horizontal trackpad gesture that starts over the
/// dial belongs to the dial for its whole life, momentum included, so a flick coasts. A vertical one, and
/// anything off the dial, is an ordinary swipe.
struct ScrollRouting {
    private var swipe = SwipeRecognizer()
    private var lock = AxisLock()
    /// The current gesture is the dial's.
    private(set) var ownsGesture = false

    mutating func route(_ sample: ScrollSample, overDial: Bool) -> ScrollAction? {
        let sign: CGFloat = sample.isInverted ? 1 : -1
        let fingerX = sample.dx * sign
        let fingerY = sample.dy * sign

        // A wheel has no fingers: a notch over the dial is a minute.
        if !sample.isPrecise {
            guard overDial else { return nil }
            let delta = fingerY != 0 ? fingerY : fingerX
            guard delta != 0 else { return nil }
            return .stepDial(delta < 0 ? 1 : -1)
        }

        if sample.isBegan {
            lock.reset()
            ownsGesture = false
        }
        // Momentum belongs to the dial only if the gesture did.
        if sample.isMomentum { return ownsGesture ? .scrubDial(fingerX) : nil }

        if ownsGesture { return .scrubDial(fingerX) }
        let result = lock.add(dx: fingerX, dy: fingerY)
        if result.justLocked, result.locked == .horizontal, overDial {
            ownsGesture = true
            return .scrubDial(result.horizontalSoFar)
        }
        return swipe.add(dx: sample.dx, dy: sample.dy, inverted: sample.isInverted, began: sample.isBegan).map(
            ScrollAction.swipe)
    }
}

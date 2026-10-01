import AppKit
import SwiftUI

/// Bouncing bars tinted with the artwork accent. The bounce eases in from rest when the bars start, so starting
/// playback reads as the music "waking up". `scale` sizes them (the peek and the Media tab use bigger ones), and
/// without `isAnimating` they rest, dimmed.
///
/// Core Animation runs the bounce in the render server, so playing music costs the app nothing per frame. (The bars
/// were a `TimelineView` that changed their frames 120 times a second, which re-laid out the whole island: about 10%
/// CPU.) `ImageRenderer` can't draw an AppKit view, so snapshots (`\.isSnapshot`) get the bars in SwiftUI, held still.
struct EqualizerView: View {
    let tint: Color
    var scale: CGFloat = 1
    var isAnimating = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    private var isMoving: Bool { isAnimating && !reduceMotion }

    var body: some View {
        Group {
            if isSnapshot {
                StillBars(tint: tint, scale: scale, isMoving: isMoving)
            } else {
                LiveBars(tint: NSColor(tint), scale: scale, isMoving: isMoving)
            }
        }
        .frame(width: EqualizerMotion.width * scale, height: EqualizerMotion.height * scale)
        .opacity(isAnimating ? 1 : 0.45)
        .accessibilityHidden(true)
    }
}

/// The bars' shape and motion, shared by the live bars and the snapshot stand-in. Sizes are at a scale of 1.
enum EqualizerMotion {
    static let barWidth: CGFloat = 3
    static let spacing: CGFloat = 2
    static let height: CGFloat = 14
    static let width = barWidth * 4 + spacing * 3
    static let restingHeights: [CGFloat] = [6, 10, 7, 9]
    /// How long the bounce takes to grow from rest.
    static let rampDuration = 0.45

    private static let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]
    private static let phases: [Double] = [0, 1.3, 2.1, 0.7]
    /// Where the snapshot stand-in is held: a moment when the four bars are at different heights.
    private static let stillTime = 0.6

    /// A bar's height `time` seconds into its bounce: 4 to 14 points, as `|sin|`, so it bounces off the floor.
    static func height(_ index: Int, at time: Double) -> CGFloat {
        4 + 10 * abs(sin(time * speeds[index] + phases[index]))
    }

    /// One bounce: `|sin|` repeats every π.
    static func period(_ index: Int) -> Double { .pi / speeds[index] }

    /// How far into its bounce a bar starts, so the four don't move together.
    static func offset(_ index: Int) -> Double { phases[index] / speeds[index] }

    /// One bounce as evenly spaced heights, from the floor back to the floor, so it loops without a seam. Every bar
    /// has the same shape; `period` and `offset` make them differ.
    static let keyframes: [CGFloat] = {
        let bounce: [CGFloat] = (0..<32).map { 4 + 10 * abs(sin(.pi * CGFloat($0) / 32)) }
        return bounce + [bounce[0]]
    }()

    static func stillHeight(_ index: Int, isMoving: Bool) -> CGFloat {
        isMoving ? height(index, at: stillTime) : restingHeights[index]
    }
}

/// The bars in SwiftUI, held still: for `ImageRenderer`.
private struct StillBars: View {
    let tint: Color
    let scale: CGFloat
    let isMoving: Bool

    var body: some View {
        HStack(spacing: EqualizerMotion.spacing * scale) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(
                        width: EqualizerMotion.barWidth * scale,
                        height: EqualizerMotion.stillHeight(index, isMoving: isMoving) * scale
                    )
            }
        }
    }
}

private struct LiveBars: NSViewRepresentable {
    let tint: NSColor
    let scale: CGFloat
    let isMoving: Bool

    func makeNSView(context: Context) -> EqualizerBarsView {
        EqualizerBarsView()
    }

    func updateNSView(_ view: EqualizerBarsView, context: Context) {
        view.configure(tint: tint, scale: scale, isMoving: isMoving)
    }
}

/// Four bar layers whose bounce is a looping Core Animation keyframe animation on each bar's height, added once and
/// then left to the render server. Layer-hosting, so AppKit leaves the layers and their animations alone.
final class EqualizerBarsView: NSView {
    static let bounceKey = "bounce"
    private static let rampKey = "ramp"
    private static let settleKey = "settle"

    let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private var scale: CGFloat = 1
    private(set) var isMoving = false

    init() {
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeBars()
    }

    func configure(tint: NSColor, scale: CGFloat, isMoving: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = tint.cgColor }
        let rescaled = scale != self.scale
        self.scale = scale
        if rescaled { placeBars() }
        CATransaction.commit()

        guard isMoving != self.isMoving || rescaled else { return }
        self.isMoving = isMoving
        if isMoving { startBouncing() } else { settle() }
    }

    /// Centers each bar vertically, at its resting height (what shows when the bounce is removed).
    private func placeBars() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = EqualizerMotion.barWidth * scale
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: EqualizerMotion.restingHeights[index] * scale)
            bar.cornerRadius = width / 2
            bar.position = CGPoint(
                x: CGFloat(index) * (EqualizerMotion.barWidth + EqualizerMotion.spacing) * scale + width / 2,
                y: bounds.midY
            )
        }
        CATransaction.commit()
    }

    private func startBouncing() {
        // The bounce grows from rest: each bar starts squeezed toward its middle and is let go.
        let ramp = CABasicAnimation(keyPath: "transform.scale.y")
        ramp.fromValue = 0.3
        ramp.toValue = 1
        ramp.duration = EqualizerMotion.rampDuration
        ramp.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: Self.settleKey)
            let bounce = CAKeyframeAnimation(keyPath: "bounds.size.height")
            bounce.values = EqualizerMotion.keyframes.map { $0 * scale }
            bounce.duration = EqualizerMotion.period(index)
            bounce.timeOffset = EqualizerMotion.offset(index)
            bounce.calculationMode = .linear
            bounce.repeatCount = .infinity
            bounce.isRemovedOnCompletion = false
            bar.add(bounce, forKey: Self.bounceKey)
            bar.add(ramp, forKey: Self.rampKey)
        }
    }

    /// Back to rest from wherever each bar is, briefly, instead of jumping.
    private func settle() {
        for bar in bars {
            let current = bar.presentation()?.bounds.height ?? bar.bounds.height
            bar.removeAnimation(forKey: Self.bounceKey)
            bar.removeAnimation(forKey: Self.rampKey)
            let settle = CABasicAnimation(keyPath: "bounds.size.height")
            settle.fromValue = current
            settle.toValue = bar.bounds.height
            settle.duration = 0.2
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bar.add(settle, forKey: Self.settleKey)
        }
    }
}

/// Set by snapshot tests: `ImageRenderer` draws an AppKit view as a placeholder, so a view that has one draws a SwiftUI
/// stand-in instead.
private struct SnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

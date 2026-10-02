import SwiftUI

extension LevelHUD {
    /// The sun for a brightness: a small one under half, a full one above.
    static func brightnessSymbol(_ fraction: Double) -> String {
        fraction < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }

    static func percent(of fraction: Double) -> Int { Int((fraction * 100).rounded()) }
}

/// A level as the island draws it beside the notch: the bar and its percent, with the glyph when it has the side to itself.
/// White on black; red only for a silent volume, beside its slashed glyph.
struct LevelReadout: View {
    let symbol: String
    let fraction: Double
    let percent: Int
    var isSilent = false
    var label: String
    var barWidth: CGFloat = Theme.Metrics.levelBarWidth
    var showsGlyph = false

    var body: some View {
        HStack(spacing: 6) {
            if showsGlyph { Glyph(systemName: symbol, tint: isSilent ? Theme.Tint.attention : nil) }
            LevelBar(fraction: fraction, tint: isSilent ? Theme.Tint.attention : nil)
                .frame(width: barWidth)
            Text("\(percent)%")
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(isSilent ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.primary))
                .contentTransition(.numericText())
                .lineLimit(1)
        }
        .animation(Theme.Motion.track, value: fraction)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(percent) percent")
    }
}

extension LevelHUD {
    /// The volume's readout, in the layout asked for.
    @MainActor @ViewBuilder
    static func volumeReadout(_ level: VolumeLevel, barWidth: CGFloat, showsGlyph: Bool) -> some View {
        LevelReadout(
            symbol: level.symbol, fraction: level.shown, percent: level.percent, isSilent: level.isSilent,
            label: level.isMuted ? "Volume (muted)" : "Volume", barWidth: barWidth, showsGlyph: showsGlyph)
    }

    @MainActor @ViewBuilder
    static func brightnessReadout(_ fraction: Double, barWidth: CGFloat, showsGlyph: Bool) -> some View {
        LevelReadout(
            symbol: brightnessSymbol(fraction), fraction: fraction, percent: percent(of: fraction), label: "Brightness",
            barWidth: barWidth, showsGlyph: showsGlyph)
    }
}

/// On an open island: the levels in the band beside the notch (brightness leading, volume trailing), fading in over what is there
/// (the tabs, the status strip) and back. Nothing about the island's size changes.
struct LevelBand: View {
    let levels: LevelHUD
    let notchWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            side { if let value = levels.brightness { LevelHUD.brightnessReadout(value, barWidth: Theme.Metrics.levelBarOpenWidth, showsGlyph: true) } }
                .opacity(levels.brightness == nil ? 0 : 1)
            Color.clear.frame(width: notchWidth)
            side { if let level = levels.volume { LevelHUD.volumeReadout(level, barWidth: Theme.Metrics.levelBarOpenWidth, showsGlyph: true) } }
                .opacity(levels.volume == nil ? 0 : 1)
        }
        .frame(height: height)
        .padding(.horizontal, ScreenGeometry.topFlare)
        .allowsHitTesting(false)
        .animation(Theme.Motion.resize, value: levels)
    }

    private func side<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.surface)
    }
}

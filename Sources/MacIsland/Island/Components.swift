import AppKit
import SwiftUI

func formatTime(_ seconds: TimeInterval) -> String {
    let total = Int(max(seconds, 0))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}

/// Dims while pressed. Shared by every button in the island.
struct IslandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// Glyph-only button with a full-size hit target, hover highlight, and an accessibility label.
struct IconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 14
    var isSelected = false
    /// The size of the button; most are the minimum hit target, the player's big ones are larger.
    var hitSize: CGFloat = Theme.Metrics.hitTarget
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isSelected ? Theme.Palette.inverse : Theme.Palette.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: hitSize, height: hitSize)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: SurfaceInk {
        if isSelected { return Theme.Palette.primary }
        return isHovering ? Theme.Palette.fill : Theme.Palette.none
    }
}

/// Small capsule button: presets and choices. Selected state is white fill with black text.
struct ChipButton: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    var accessibilityLabel: String?
    /// Stretch to share a row equally with other chips.
    var fillsWidth = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .font(Theme.Typography.bodyEmphasized)
            .foregroundStyle(isSelected ? Theme.Palette.inverse : Theme.Palette.primary)
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background(
                isSelected ? Theme.Palette.primary : (isHovering ? Theme.Palette.fillHover : Theme.Palette.fill),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(IslandButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Two or more mutually exclusive choices in one capsule. Selected segment is a white fill.
struct SegmentedChoice<Option: Hashable & Identifiable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button { onSelect(option) } label: {
                    Text(title(option))
                        .font(Theme.Typography.bodyEmphasized)
                        .foregroundStyle(isSelected ? Theme.Palette.inverse : Theme.Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .background(isSelected ? Theme.Palette.primary : Theme.Palette.none, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(IslandButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: 24)
        .background(Theme.Palette.fill, in: Capsule())
    }
}

/// Thin capsule slider. `onChange` fires continuously while dragging; `onCommit` fires on release.
struct IslandSlider: View {
    var value: Double
    /// A live color; `nil` is the palette's primary ink.
    var tint: Color?
    let label: String
    var valueDescription: String?
    var onChange: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?

    @State private var dragValue: Double?
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geometry in
            let shown = min(max(dragValue ?? value, 0), 1)
            let active = isEnabled && (isHovering || dragValue != nil)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.fillHover)
                Capsule().fill(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(Theme.Palette.primary)).frame(width: geometry.size.width * shown)
            }
            .frame(height: active ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = fraction(gesture.location.x, width: geometry.size.width)
                        dragValue = newValue
                        onChange?(newValue)
                    }
                    .onEnded { gesture in
                        onCommit?(fraction(gesture.location.x, width: geometry.size.width))
                        dragValue = nil
                    }
            )
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: Theme.Metrics.sliderHitHeight)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueDescription ?? "\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            let newValue = min(max(value + (direction == .increment ? step : -step), 0), 1)
            onChange?(newValue)
            onCommit?(newValue)
        }
    }

    private func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(Theme.Palette.fill)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Theme.Palette.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Countdown ring used by the timer in both compact and expanded states.
struct ProgressRing: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Palette.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// A bolt with a ring that draws once around it, starting from the top. Under Reduce Motion
/// the ring is simply there.
struct ChargingBadge: View {
    let size: CGFloat

    @State private var drawn = false

    var body: some View {
        let animates = !Theme.Motion.reduceMotion
        ZStack {
            Circle()
                .trim(from: 0, to: drawn || !animates ? 1 : 0)
                .stroke(Theme.Tint.positive, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Theme.Tint.positive)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animates else { return }
            withAnimation(.easeInOut(duration: 1.0)) { drawn = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Charging")
    }
}

/// A standalone symbol in a fixed square, so glyphs of different widths (bolt, stopwatch, touchid)
/// share one center and don't nudge their neighbors when they swap.
struct Glyph: View {
    let systemName: String
    /// A live color; `nil` is the palette's primary ink.
    var tint: Color?

    var body: some View {
        Image(systemName: systemName)
            .font(Theme.Typography.glyph)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(Theme.Palette.primary))
            .frame(width: Theme.Metrics.glyphSlot, height: Theme.Metrics.glyphSlot)
            .accessibilityHidden(true)
    }
}

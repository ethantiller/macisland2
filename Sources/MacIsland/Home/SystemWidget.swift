import SwiftUI

/// CPU, memory, battery, and how hot the Mac is running. It reads only while it is on screen (a `.task` that ends with the view), and
/// red appears only for "needs you", beside a glyph: memory pressure critical, the Mac running hot, or a battery at 20% or less that
/// isn't charging.
struct SystemWidget: View {
    let model: SystemModel
    var size = GridSize(2, 1)

    var body: some View {
        Group {
            if let reading = model.reading {
                content(reading)
            } else {
                Image(systemName: "cpu")
                    .font(Theme.Typography.glyph)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBox()
        .task { await model.run() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.summary(model.reading))
    }

    @ViewBuilder
    private func content(_ reading: SystemReading) -> some View {
        switch (size.columns, size.rows) {
        case (3, 2):
            rows(reading)
        case (3, _):
            columns(Self.cells(reading, includeBattery: true))
        case (2, _):
            columns(Array(Self.cells(reading, includeBattery: false).prefix(2)))
        default:
            columns([Self.cells(reading, includeBattery: false)[0]])
        }
    }

    // MARK: What is shown

    struct Cell: Equatable {
        let value: String
        let caption: String
        var needsAttention = false
    }

    /// CPU and memory, then the battery, or how hot the Mac is on one that has none.
    static func cells(_ reading: SystemReading, includeBattery: Bool) -> [Cell] {
        var cells = [
            Cell(value: reading.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "\u{2013}", caption: "CPU"),
            Cell(
                value: "\(Int((reading.memoryFraction * 100).rounded()))%", caption: "Memory",
                needsAttention: reading.memoryNeedsAttention),
        ]
        guard includeBattery else { return cells }
        if let battery = reading.battery {
            cells.append(
                Cell(value: "\(battery.percent)%", caption: "Battery", needsAttention: reading.batteryNeedsAttention))
        } else {
            cells.append(
                Cell(
                    value: SystemMath.thermalWords(reading.thermal), caption: "Thermal",
                    needsAttention: reading.thermalNeedsAttention))
        }
        return cells
    }

    static func summary(_ reading: SystemReading?) -> String {
        guard let reading else { return "System" }
        return Self.cells(reading, includeBattery: true).map { "\($0.caption) \($0.value)" }.joined(separator: ", ")
    }

    // MARK: Layouts

    private func columns(_ cells: [Cell]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                if index > 0 {
                    Rectangle().fill(Theme.Palette.fillHover).frame(width: 1).padding(.vertical, 14)
                }
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        if cell.needsAttention { attentionGlyph }
                        Text(cell.value)
                            .font(cells.count == 1 ? Theme.Typography.largeNumeral : Theme.Typography.compactNumeral)
                            .foregroundStyle(cell.needsAttention ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.primary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text(cell.caption)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var attentionGlyph: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Tint.attention)
            .accessibilityHidden(true)
    }

    /// 3 by 2: each reading on its own row with a bar, and how hot the Mac is in words.
    private func rows(_ reading: SystemReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row("CPU", fraction: reading.cpu ?? 0, value: Self.cells(reading, includeBattery: false)[0].value)
            row(
                "Memory", fraction: reading.memoryFraction, value: Self.cells(reading, includeBattery: false)[1].value,
                attention: reading.memoryNeedsAttention)
            if let battery = reading.battery {
                row(
                    "Battery", fraction: Double(battery.percent) / 100, value: "\(battery.percent)%",
                    attention: reading.batteryNeedsAttention)
            }
            HStack(spacing: 6) {
                if reading.thermalNeedsAttention { attentionGlyph }
                Image(systemName: "thermometer.medium")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(reading.thermalNeedsAttention ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.secondary))
                    .accessibilityHidden(true)
                Text(SystemMath.thermalWords(reading.thermal))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(reading.thermalNeedsAttention ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.secondary))
            }
        }
        .padding(.horizontal, 12)
    }

    private func row(_ title: String, fraction: Double, value: String, attention: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(width: 54, alignment: .leading)
            LevelBar(fraction: fraction, tint: attention ? Theme.Tint.attention : nil)
            if attention { attentionGlyph }
            Text(value)
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(attention ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.primary))
                .frame(width: 40, alignment: .trailing)
        }
    }
}

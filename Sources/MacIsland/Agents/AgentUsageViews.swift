import SwiftUI

/// The modes of the Agents module.
enum AgentsMode: String, CaseIterable, Identifiable {
    case now = "Now"
    case usage = "Usage"
    case stats = "Stats"

    var id: Self { self }
}

/// Numbers and times as the Agents views word them.
enum AgentUsageFormat {
    /// "$4.20", "$128", or "at least $4.20" when some model had no price.
    static func dollars(_ value: Double, atLeast: Bool = false) -> String {
        let text = value >= 100 ? String(format: "$%.0f", value) : String(format: "$%.2f", value)
        return atLeast ? "at least " + text : text
    }

    /// "820", "12.4K", "142M", "1.3B".
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch value {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return trimmed(value / 1_000) + "K"
        case ..<1_000_000_000: return trimmed(value / 1_000_000) + "M"
        default: return trimmed(value / 1_000_000_000) + "B"
        }
    }

    private static func trimmed(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value).replacingOccurrences(of: ".0", with: "")
    }

    /// "94%", or "<1%" for a sliver that would round to nothing.
    static func share(_ fraction: Double) -> String {
        let value = safeInt((fraction * 100).rounded())
        return value == 0 && fraction > 0 ? "<1%" : "\(value)%"
    }

    /// "62%" used, or "38% left".
    static func percent(_ used: Double, showsLeft: Bool) -> String {
        let value = safeInt((showsLeft ? 100 - used : used).rounded())
        return showsLeft ? "\(max(value, 0))% left" : "\(value)%"
    }

    /// "7:10 PM", or "Fri 7:00 PM" when it is a day or more away.
    static func reset(_ date: Date, now: Date = Date()) -> String {
        if date.timeIntervalSince(now) > 20 * 3600 {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "Resets 7:10 PM", with "as of 3:10 PM" when the reading is old.
    static func resetLine(_ limit: AgentLimit, now: Date = Date()) -> String {
        var parts: [String] = []
        if let resets = limit.resetsAt { parts.append("Resets " + reset(resets, now: now)) }
        if let asOf = limit.asOf { parts.append("as of " + asOf.formatted(date: .omitted, time: .shortened)) }
        if limit.isEstimate { parts.append("estimated") }
        if parts.isEmpty { return "No reading yet" }
        return parts.joined(separator: ", ")
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Prices as of Oct 1".
    static func pricesLine(_ pricing: AgentPricing) -> String? {
        guard !pricing.updated.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: pricing.updated) else { return "Prices as of " + pricing.updated }
        return "Prices as of " + date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: Now: the limits

/// One plan limit: its name, a bar, the percent, and when it resets. The bar and percent turn red at the threshold.
struct AgentLimitRow: View {
    let limit: AgentLimit
    let threshold: Int
    let showsLeft: Bool

    private var isOver: Bool { limit.isOver(threshold: Double(threshold)) }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(limit.agent == .claudeCode ? "Claude" : "Codex") \(limit.kind.title)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(width: 92, alignment: .leading)
            // The bar is always drawn: with no reading it is empty, and the words say why.
            LevelBar(fraction: (limit.percent ?? 0) / 100, tint: isOver ? Theme.Tint.attention : nil)
            if isOver {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Tint.attention)
                    .accessibilityHidden(true)
            }
            Text(limit.percent.map { AgentUsageFormat.percent($0, showsLeft: showsLeft) } ?? "\u{2013}")
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(isOver ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.primary))
                .frame(width: 58, alignment: .trailing)
            Text(AgentUsageFormat.resetLine(limit))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: Theme.Metrics.limitResetWidth, alignment: .trailing)
        }
        .frame(height: 20)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Usage

/// What the agents used over a range: the value at API prices, what the cache saved, how the tokens split (a donut), and the top models and projects.
struct AgentUsageView: View {
    let usage: AgentUsageModel
    let range: UsageRange

    var body: some View {
        if let snapshot = usage.snapshot {
            let summary = AgentUsageSummary.make(
                buckets: snapshot.buckets, range: range, now: Date(), pricing: usage.pricing)
            VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
                HStack(alignment: .center, spacing: 18) {
                    valueColumn(summary)
                    TokenDonut(shares: summary.shares, total: summary.tokens)
                    TokenLegend(shares: summary.shares)
                }
                HStack(alignment: .top, spacing: 18) {
                    RankColumn(title: "Models", rows: summary.models)
                    RankColumn(title: "Projects", rows: summary.projects)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(usage.isEnabled ? "Reading history\u{2026}" : "Turn on AI Agents to see usage.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The value at API prices, what the cache saved, and when the prices are from.
    private func valueColumn(_ summary: AgentUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AgentUsageFormat.dollars(summary.value, atLeast: summary.isLowerBound))
                .font(Theme.Typography.largeNumeral)
                .foregroundStyle(Theme.Palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("at API prices")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
            if summary.cacheSaving > 0 {
                Text("Cache saved " + AgentUsageFormat.dollars(summary.cacheSaving))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            if let line = AgentUsageFormat.pricesLine(usage.pricing) {
                Text(line)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .frame(width: 150, alignment: .leading)
    }
}

/// The top three of a ranking, each with its value or, without a price, its tokens.
struct RankColumn: View {
    let title: String
    let rows: [RankedUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
            ForEach(rows.prefix(3)) { row in
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.value.map { AgentUsageFormat.dollars($0) } ?? AgentUsageFormat.tokens(row.tokens))
                        .font(Theme.Typography.numeral)
                        .foregroundStyle(Theme.Palette.secondary)
                }
                .frame(height: 18)
            }
            if rows.isEmpty {
                Text("None yet")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: The token mix

extension TokenKind {
    /// Three steps of white, so the legend and the ring agree without color.
    var style: AnyShapeStyle {
        switch self {
        case .input: AnyShapeStyle(Theme.Palette.activitySteps[4])
        case .output: AnyShapeStyle(Theme.Palette.activitySteps[3])
        case .cache: AnyShapeStyle(Theme.Palette.activitySteps[2])
        }
    }
}

/// A ring cut into the token kinds, with the total in the middle.
struct TokenDonut: View {
    let shares: [TokenShare]
    let total: Int

    private var size: CGFloat { Theme.Metrics.tokenDonutSize }
    private var lineWidth: CGFloat { Theme.Metrics.tokenDonutWidth }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Palette.fill, lineWidth: lineWidth)
            ForEach(arcs, id: \.kind) { arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(arc.kind.style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(AgentUsageFormat.tokens(total))
                    .font(Theme.Typography.statValue)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("tokens")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            .frame(width: size - 2 * lineWidth - 6)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tokens by kind")
        .accessibilityValue(
            shares.map { "\($0.kind.rawValue) \(AgentUsageFormat.share($0.fraction))" }.joined(separator: ", "))
    }

    /// Each kind's start and end around the ring, with a hairline gap between kinds that are there.
    private var arcs: [(kind: TokenKind, start: Double, end: Double)] {
        let present = shares.filter { $0.tokens > 0 }
        let gap = present.count > 1 ? 0.012 : 0
        var from = 0.0
        return present.map { share in
            defer { from += share.fraction }
            return (share.kind, from + gap / 2, max(from + share.fraction - gap / 2, from + gap / 2 + 0.001))
        }
    }
}

/// The kinds beside the donut: a swatch, the name, its share, and its tokens.
struct TokenLegend: View {
    let shares: [TokenShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(shares) { share in
                HStack(spacing: 8) {
                    Circle()
                        .fill(share.kind.style)
                        .frame(width: 8, height: 8)
                    Text(share.kind.rawValue)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.primary)
                    Spacer(minLength: 4)
                    Text(AgentUsageFormat.share(share.fraction))
                        .font(Theme.Typography.compactNumeral)
                        .foregroundStyle(Theme.Palette.primary)
                    Text(AgentUsageFormat.tokens(share.tokens))
                        .font(Theme.Typography.numeral)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// The modes of the Agents module.
enum AgentsMode: String, CaseIterable, Identifiable {
    case now = "Now"
    case usage = "Usage"
    case activity = "Activity"

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

    /// "62%" used, or "38% left".
    static func percent(_ used: Double, showsLeft: Bool) -> String {
        let value = Int((showsLeft ? 100 - used : used).rounded())
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
            if let percent = limit.percent {
                LevelBar(fraction: percent / 100, tint: isOver ? Theme.Tint.attention : nil)
                if isOver {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Tint.attention)
                        .accessibilityHidden(true)
                }
                Text(AgentUsageFormat.percent(percent, showsLeft: showsLeft))
                    .font(Theme.Typography.compactNumeral)
                    .foregroundStyle(isOver ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.primary))
                    .frame(width: 58, alignment: .trailing)
            } else {
                Spacer(minLength: 0)
            }
            Text(AgentUsageFormat.resetLine(limit))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(1)
                .frame(width: limit.percent == nil ? nil : 128, alignment: .trailing)
        }
        .frame(height: 20)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Usage

/// What the agents used over a range: the value at API prices, tokens, what the cache saved, and the top models and projects.
struct AgentUsageView: View {
    let usage: AgentUsageModel
    let range: UsageRange

    var body: some View {
        if let snapshot = usage.snapshot {
            let summary = AgentUsageSummary.make(
                buckets: snapshot.buckets, range: range, now: Date(), pricing: usage.pricing)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AgentUsageFormat.dollars(summary.value, atLeast: summary.isLowerBound))
                        .font(Theme.Typography.largeNumeral)
                        .foregroundStyle(Theme.Palette.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("at API prices")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                    Text("\(AgentUsageFormat.tokens(summary.tokens)) tokens")
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
                .frame(width: 140, alignment: .leading)
                RankColumn(title: "Models", rows: summary.models)
                RankColumn(title: "Projects", rows: summary.projects)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(usage.isEnabled ? "Reading history\u{2026}" : "Turn on AI Agents to see usage.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

// MARK: Activity

/// The last 91 days, a week to a column. Hovering a day names it in the header.
struct AgentActivityMapView: View {
    let usage: AgentUsageModel
    @Binding var hovered: ActivityMap.Cell?

    var body: some View {
        if let snapshot = usage.snapshot {
            let map = ActivityMap.make(buckets: snapshot.buckets, now: Date())
            HStack(alignment: .top, spacing: 18) {
                HStack(spacing: Theme.Metrics.activityGap) {
                    ForEach(Array(map.weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: Theme.Metrics.activityGap) {
                            ForEach(week) { cell in
                                RoundedRectangle(cornerRadius: Theme.Metrics.activityCell / 4, style: .continuous)
                                    .fill(cell.date == nil ? Theme.Palette.none : Theme.Palette.activitySteps[cell.level])
                                    .frame(width: Theme.Metrics.activityCell, height: Theme.Metrics.activityCell)
                                    .onHover { inside in
                                        if inside, cell.date != nil {
                                            hovered = cell
                                        } else if hovered?.id == cell.id {
                                            hovered = nil
                                        }
                                    }
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(map.streak)")
                        .font(Theme.Typography.largeNumeral)
                        .foregroundStyle(Theme.Palette.primary)
                    Text(map.streak == 1 ? "day in a row" : "days in a row")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                    Text("\(map.activeDays) active days")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(map.activeDays) active days in the last 91, \(map.streak) in a row")
        } else {
            Text(usage.isEnabled ? "Reading history\u{2026}" : "Turn on AI Agents to see activity.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

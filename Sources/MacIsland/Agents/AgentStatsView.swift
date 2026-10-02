import SwiftUI

/// Which tool the Stats mode counts.
enum StatsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case claude = "Claude"
    case codex = "Codex"

    var id: Self { self }

    var agent: AgentKind? {
        switch self {
        case .all: nil
        case .claude: .claudeCode
        case .codex: .codex
        }
    }

    init(agent: AgentKind?) {
        switch agent {
        case nil: self = .all
        case .claudeCode?: self = .claude
        case .codex?: self = .codex
        }
    }
}

extension AgentUsageFormat {
    /// "4d 13h", "3h 20m", or "12m".
    static func span(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 24 * 60 { return "\(minutes / (24 * 60))d \((minutes / 60) % 24)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    /// "10 PM".
    static func hour(_ hour: Int) -> String {
        "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")"
    }
}

/// Stats: a year of days to a cell, and what the agents did over a range as eight numbers. White only: this is history, not live.
struct AgentStatsView: View {
    let usage: AgentUsageModel
    let agent: AgentKind?
    let range: StatsRange
    @Binding var hovered: YearMap.Cell?
    let onRange: (StatsRange) -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let snapshot = usage.snapshot {
            if snapshot.buckets.filter({ agent == nil || $0.agent == agent }).isEmpty {
                empty
            } else {
                content(snapshot)
            }
        } else {
            Text(usage.isEnabled ? "Reading history\u{2026}" : "Turn on AI Agents to see stats.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("No AI use yet.")
                .font(Theme.Typography.bodyEmphasized)
                .foregroundStyle(Theme.Palette.secondary)
            if !AgentLogLocations.hasLogs() {
                Text("Couldn\u{2019}t find the logs of Claude Code or Codex.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ snapshot: AgentUsageSnapshot) -> some View {
        let now = Date()
        let map = YearMap.make(buckets: snapshot.buckets, now: now, agent: agent)
        let stats = AgentStats.make(snapshot: snapshot, agent: agent, range: range, now: now, pricing: usage.pricing)
        let firstDay: Int? = range.days.flatMap { days in
            Calendar.current.date(byAdding: .day, value: -(days - 1), to: now).map { UsageDay.key($0, calendar: .current) }
        }
        return VStack(alignment: .leading, spacing: 4) {
            monthRow(map)
            HStack(alignment: .top, spacing: Theme.Metrics.yearLabelGap) {
                weekdayLabels
                grid(map, firstDay: firstDay)
            }
            HStack(spacing: 10) {
                SegmentedChoice(options: StatsRange.allCases, selection: range, title: \.rawValue, onSelect: onRange)
                    .frame(width: Theme.Metrics.agentsStatsRangeWidth)
                Spacer(minLength: 0)
                if let fact = stats.funFact {
                    Text(fact)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(1)
                }
            }
            tiles(stats)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(stats, map: map))
    }

    private var pitch: CGFloat { Theme.Metrics.yearCell + Theme.Metrics.yearGap }
    private var labelWidth: CGFloat { Theme.Metrics.yearWeekdayLabelWidth }

    private func monthRow(_ map: YearMap) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(map.monthLabels, id: \.column) { label in
                Text(label.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(label.column) * pitch)
            }
        }
        .frame(height: Theme.Metrics.yearMonthRowHeight, alignment: .topLeading)
        .padding(.leading, labelWidth + Theme.Metrics.yearLabelGap)
    }

    /// Monday, Wednesday, and Friday, on their rows.
    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: Theme.Metrics.yearGap) {
            ForEach(0..<YearMap.rows, id: \.self) { row in
                Text(row == 1 ? "M" : row == 3 ? "W" : row == 5 ? "F" : "")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .frame(width: labelWidth, height: Theme.Metrics.yearCell, alignment: .trailing)
                    .minimumScaleFactor(0.5)
            }
        }
        .accessibilityHidden(true)
    }

    private func grid(_ map: YearMap, firstDay: Int?) -> some View {
        HStack(spacing: Theme.Metrics.yearGap) {
            ForEach(Array(map.weeks.enumerated()), id: \.offset) { column, week in
                VStack(spacing: Theme.Metrics.yearGap) {
                    ForEach(week) { cell in
                        RoundedRectangle(cornerRadius: Theme.Metrics.yearCellRadius, style: .continuous)
                            .fill(style(for: cell))
                            .frame(width: Theme.Metrics.yearCell, height: Theme.Metrics.yearCell)
                            .opacity(isOutside(cell, firstDay: firstDay) ? 0.35 : 1)
                            .scaleEffect(hovered?.id == cell.id ? 1.5 : 1)
                            .animation(Theme.Motion.track, value: hovered?.id)
                            .onHover { inside in
                                if inside, cell.date != nil {
                                    hovered = cell
                                } else if hovered?.id == cell.id {
                                    hovered = nil
                                }
                            }
                    }
                }
                .opacity(appeared ? 1 : 0)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.25).delay(Double(column) * 0.012),
                    value: appeared)
            }
        }
        .accessibilityHidden(true)
    }

    private func style(for cell: YearMap.Cell) -> AnyShapeStyle {
        if cell.date == nil { return AnyShapeStyle(Theme.Palette.none) }
        return AnyShapeStyle(cell.level == 0 ? Theme.Palette.fill : Theme.Palette.activitySteps[cell.level])
    }

    /// A day before the range starts: drawn dim, so the range reads on the map.
    private func isOutside(_ cell: YearMap.Cell, firstDay: Int?) -> Bool {
        guard cell.date != nil, let firstDay else { return false }
        return cell.day < firstDay
    }

    private func tiles(_ stats: AgentStats) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 4)
        let value = stats.value == 0 && stats.isLowerBound ? "\u{2013}" : AgentUsageFormat.dollars(stats.value) + (stats.isLowerBound ? "+" : "")
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            tile(AgentUsageFormat.tokens(stats.tokens), "tokens")
            tile(value, "API value")
            tile("\(stats.sessions)", "sessions")
            tile(stats.longestSession > 0 ? AgentUsageFormat.span(stats.longestSession) : "\u{2013}", "longest session")
            tile(stats.favoriteModel ?? "\u{2013}", "favorite model")
            tile("\(stats.activeDays) of \(stats.rangeDays)", "active days")
            tile(stats.currentStreak == 1 ? "1 day" : "\(stats.currentStreak) days", "streak")
            tile(stats.peakHour.map(AgentUsageFormat.hour) ?? "\u{2013}", "peak hour")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Theme.Typography.statValue)
                .foregroundStyle(Theme.Palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(1)
        }
        .frame(height: Theme.Metrics.statTileHeight, alignment: .topLeading)
    }

    private func summary(_ stats: AgentStats, map: YearMap) -> String {
        "Stats, \(range.rawValue): \(AgentUsageFormat.tokens(stats.tokens)) tokens, \(stats.sessions) sessions, "
            + "\(stats.activeDays) of \(stats.rangeDays) days active, \(stats.currentStreak) day streak"
    }
}

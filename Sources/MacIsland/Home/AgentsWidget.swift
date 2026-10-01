import SwiftUI

/// The agents' plan limits and today's value, on Home. Offered only while AI Agents is on. It asks for a fresh reading when it appears
/// and reads nothing else; red appears only for a window at its threshold, beside a glyph.
struct AgentsWidget: View {
    let usage: AgentUsageModel
    let settings: AppSettings
    var size = GridSize(2, 1)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetBox()
            .task { await usage.refresh() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summary)
    }

    private var limits: [AgentLimit] { usage.snapshot?.limits ?? [] }

    private var today: AgentUsageSummary? {
        usage.snapshot.map {
            AgentUsageSummary.make(buckets: $0.buckets, range: .today, now: Date(), pricing: usage.pricing)
        }
    }

    private var summary: String {
        var parts = limits.compactMap { limit in
            limit.percent.map { "\(limit.agent.rawValue) \(limit.kind.title) \(AgentUsageFormat.percent($0, showsLeft: settings.showsLimitsLeft))" }
        }
        if let today { parts.append("Today " + AgentUsageFormat.dollars(today.value, atLeast: today.isLowerBound)) }
        return parts.isEmpty ? "AI Agents" : parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var content: some View {
        if usage.snapshot == nil {
            Image(systemName: "sparkles")
                .font(Theme.Typography.glyph)
                .foregroundStyle(Theme.Palette.tertiary)
                .accessibilityHidden(true)
        } else if size.columns >= 3 {
            HStack(spacing: 0) {
                let rings = Array(limits.filter { $0.percent != nil && $0.agent == preferredAgent }.prefix(2))
                ForEach(rings) { limit in
                    ring(limit)
                    divider
                }
                valueCell
            }
        } else {
            if let busiest = usage.snapshot?.busiestLimit {
                ring(busiest)
            } else {
                valueCell
            }
        }
    }

    /// The agent whose limits the 3 by 1 shows: Claude, or Codex if it is the only one that has any.
    private var preferredAgent: AgentKind {
        limits.contains { $0.agent == .claudeCode && $0.percent != nil } ? .claudeCode : .codex
    }

    private var divider: some View {
        Rectangle().fill(Theme.Palette.fillHover).frame(width: 1).padding(.vertical, 14)
    }

    private func ring(_ limit: AgentLimit) -> some View {
        let isOver = limit.isOver(threshold: Double(settings.agentLimitThreshold))
        let percent = limit.percent ?? 0
        return HStack(spacing: 8) {
            ProgressRing(
                progress: percent / 100, tint: isOver ? Theme.Tint.attention : Theme.Tint.neutral, lineWidth: 4
            )
            .frame(width: Theme.Metrics.agentsRing, height: Theme.Metrics.agentsRing)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if isOver {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Tint.attention)
                            .accessibilityHidden(true)
                    }
                    Text(AgentUsageFormat.percent(percent, showsLeft: settings.showsLimitsLeft))
                        .font(Theme.Typography.compactNumeral)
                        .foregroundStyle(isOver ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.primary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(limit.kind.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var valueCell: some View {
        VStack(spacing: 2) {
            Text(today.map { AgentUsageFormat.dollars($0.value, atLeast: $0.isLowerBound) } ?? "\u{2013}")
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Today")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

import SwiftUI

extension AgentTask {
    /// The model as a short name: "claude-opus-4-5-20251101" is "opus-4-5".
    var modelName: String? {
        guard var name = model, !name.isEmpty else { return nil }
        if name.hasPrefix("claude-") { name.removeFirst("claude-".count) }
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) { name.removeSubrange(range) }
        return name
    }

    /// "Claude Code, opus-4-5" or just the agent.
    var subtitle: String { [agent.rawValue, modelName].compactMap { $0 }.joined(separator: ", ") }
}

/// The Agents module: what the agents are working on now and their plan limits, what they used, and when. Read from the logs Claude
/// Code and Codex keep in the home folder, and from the Claude app's usage file when it has one.
struct AgentsView: View {
    let viewModel: IslandViewModel
    @State private var hoveredDay: YearMap.Cell?

    private var usage: AgentUsageModel { viewModel.agents.usage }

    /// The filter is only worth showing once both tools have been used.
    private var hasBothAgents: Bool {
        let agents = Set(usage.snapshot?.buckets.map(\.agent) ?? [])
        return agents.count > 1
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            switch viewModel.agentsMode {
            case .now: AgentsNowView(viewModel: viewModel)
            case .usage: AgentUsageView(usage: usage, range: viewModel.usageRange)
            case .stats:
                AgentStatsView(
                    usage: usage, agent: viewModel.statsAgent, range: viewModel.statsRange, hovered: $hoveredDay,
                    onRange: viewModel.setStatsRange)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await usage.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SegmentedChoice(options: AgentsMode.allCases, selection: viewModel.agentsMode, title: \.rawValue) {
                viewModel.setAgentsMode($0)
            }
            .frame(width: Theme.Metrics.agentsModeWidth)
            Spacer(minLength: 0)
            switch viewModel.agentsMode {
            case .now:
                EmptyView()
            case .usage:
                SegmentedChoice(options: UsageRange.allCases, selection: viewModel.usageRange, title: \.rawValue) {
                    viewModel.setUsageRange($0)
                }
                .frame(width: Theme.Metrics.agentsRangeWidth)
            case .stats:
                if let day = hoveredDay, let date = day.date {
                    Text("\(AgentUsageFormat.day(date)) \u{00B7} \(day.tokens == 0 ? "no use" : AgentUsageFormat.tokens(day.tokens) + " tokens")")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                } else if hasBothAgents {
                    SegmentedChoice(options: StatsFilter.allCases, selection: StatsFilter(agent: viewModel.statsAgent), title: \.rawValue) {
                        viewModel.setStatsAgent($0.agent)
                    }
                    .frame(width: Theme.Metrics.agentsFilterWidth)
                }
            }
        }
    }
}

/// Now: the tasks that are running, then each agent's plan limits.
struct AgentsNowView: View {
    let viewModel: IslandViewModel

    var body: some View {
        let tasks = viewModel.agents.liveTasks
        let settings = viewModel.settings
        let limits = viewModel.agents.usage.snapshot?.limits ?? []
        VStack(spacing: 4) {
            if tasks.isEmpty {
                VStack(spacing: 4) {
                    Label("Nothing is running.", systemImage: "sparkles")
                        .font(Theme.Typography.bodyEmphasized)
                        .foregroundStyle(Theme.Palette.secondary)
                    if !AgentLogLocations.hasLogs() {
                        Text("Couldn\u{2019}t find the logs of Claude Code or Codex.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: Theme.Metrics.rowSpacing) {
                    ForEach(tasks.prefix(limits.count > 2 ? 1 : 2)) { AgentTaskRow(task: $0, detail: .row) }
                }
            }
            if !limits.isEmpty {
                VStack(spacing: 2) {
                    ForEach(limits) {
                        AgentLimitRow(limit: $0, threshold: settings.agentLimitThreshold, showsLeft: settings.showsLimitsLeft)
                    }
                    if settings.readsClaudeCode, viewModel.agents.usage.snapshot?.hasClaudePlanFile == false {
                        Text("Estimated from this Mac. The Claude app writes limits while its menu-bar item is on.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// One running task, drawn the same in the peek and in Now: the agent's mark, what it is doing, and how long it has run.
struct AgentTaskRow: View {
    enum Detail {
        /// The mark, the title over "project · Model", and the time.
        case row
        /// The peek's single task: a second line with the tokens used, and the context left as a bar.
        case full
    }

    let task: AgentTask
    var detail: Detail = .row
    /// Tasks beyond the ones shown, as "+1" before the time.
    var more = 0

    var body: some View {
        switch detail {
        case .row: row
        case .full: full
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            AgentMark(agent: task.agent, size: 22).frame(width: Theme.Metrics.agentMarkBox, height: Theme.Metrics.agentMarkBox)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.displayTitle)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                Text(task.detailLine)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if more > 0 {
                Text("+\(more)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            ElapsedText(since: task.startedAt, tint: Theme.Tint.working)
        }
        .frame(height: Theme.Metrics.agentMarkBox)
        .accessibilityElement(children: .combine)
    }

    private var full: some View {
        VStack(spacing: 3) {
            HStack(spacing: 10) {
                AgentMark(agent: task.agent, size: 22).frame(width: Theme.Metrics.agentMarkBox, height: Theme.Metrics.agentMarkBox)
                Text(task.displayTitle)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ElapsedText(since: task.startedAt, tint: Theme.Tint.working)
            }
            .frame(height: Theme.Metrics.agentMarkBox)
            HStack {
                Text(task.detailLine)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(AgentUsageFormat.tokens(task.tokens.total)) tokens")
                    .font(Theme.Typography.numeral)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            if let context = task.contextFraction {
                HStack(spacing: 8) {
                    LevelBar(fraction: context)
                    Text("\(Int((context * 100).rounded()))%")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Context used \(Int((context * 100).rounded())) percent")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension AgentTask {
    /// "island · Opus 4.5", or just the folder before the model is known.
    var detailLine: String {
        [project, model.map(AgentLogParser.prettyModel)].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// How much of the model's context is used, 0 to 1; nil when it isn't known.
    var contextFraction: Double? {
        guard let context, context.window > 0 else { return nil }
        return min(Double(context.used) / Double(context.window), 1)
    }
}

/// Hover while an agent works: one task in full, or two as rows (a third shows as "+1").
struct AgentPeekView: View {
    let agents: AgentActivity

    var body: some View {
        let tasks = agents.liveTasks
        VStack(spacing: Theme.Metrics.rowSpacing) {
            if tasks.count == 1, let task = tasks.first {
                AgentTaskRow(task: task, detail: .full)
            } else {
                ForEach(Array(tasks.prefix(2).enumerated()), id: \.element.id) { index, task in
                    AgentTaskRow(task: task, detail: .row, more: index == 1 ? max(tasks.count - 2, 0) : 0)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

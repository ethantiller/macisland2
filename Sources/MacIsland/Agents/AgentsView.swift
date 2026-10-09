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
                AgentFilterMenu(filter: viewModel.statsFilter) { viewModel.setStatsAgent($0.agent) }
            }
        }
    }
}

/// Now: the tasks that are running (or one quiet line saying none are), then the plan limits as bars: Claude's session and week
/// always, Codex's when it has reported any.
struct AgentsNowView: View {
    let viewModel: IslandViewModel

    /// Claude's two windows, each one drawn even without a reading (an empty bar that says so), then whatever else there is.
    static func shownLimits(_ limits: [AgentLimit], readsClaude: Bool) -> [AgentLimit] {
        var shown: [AgentLimit] = []
        if readsClaude {
            for kind in AgentLimitKind.allCases {
                shown.append(
                    limits.first { $0.agent == .claudeCode && $0.kind == kind }
                        ?? AgentLimit(agent: .claudeCode, kind: kind, percent: nil, resetsAt: nil, asOf: nil))
            }
        }
        return shown + limits.filter { $0.agent != .claudeCode }
    }

    /// How tall Now is: the usual height, plus what the running tasks take over the one quiet line, so the runner under the limits keeps
    /// its room. At most as tall as an island ever gets.
    static func contentHeight(tasks: Int, limits: Int) -> CGFloat {
        let shown = min(tasks, limits > 2 ? 1 : 2)
        guard shown > 0 else { return Theme.Metrics.agentsHeight }
        let rows = CGFloat(shown) * Theme.Metrics.agentMarkBox + CGFloat(shown - 1) * Theme.Metrics.rowSpacing
        return min(Theme.Metrics.agentsHeight + rows - Theme.Metrics.agentIdleLineHeight, Theme.Metrics.homeMaxContentHeight)
    }

    var body: some View {
        let tasks = viewModel.agents.liveTasks
        let settings = viewModel.settings
        let limits = Self.shownLimits(
            viewModel.agents.usage.snapshot?.limits ?? [], readsClaude: settings.readsClaudeCode)
        VStack(alignment: .leading, spacing: 8) {
            if tasks.isEmpty {
                let idle =
                    AgentLogLocations.hasLogs() ? "Nothing is running" : "Couldn\u{2019}t find Claude Code or Codex logs"
                Label(idle, systemImage: "sparkles")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: Theme.Metrics.rowSpacing) {
                    ForEach(tasks.prefix(limits.count > 2 ? 1 : 2)) { AgentTaskRow(task: $0, detail: .row) }
                }
            }
            if !limits.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan limits")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
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
            // What is left of the tab, if there is room for it: a little Claude running and jumping, by itself, whether or not an
            // agent is working.
            GeometryReader { proxy in
                if proxy.size.height >= Theme.Metrics.runnerHeight {
                    ClaudeRunnerView()
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
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
                    Text("\(safeInt((context * 100).rounded()))%")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Context used \(safeInt((context * 100).rounded())) percent")
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

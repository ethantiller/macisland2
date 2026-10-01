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
    @State private var hoveredDay: ActivityMap.Cell?

    private var usage: AgentUsageModel { viewModel.agents.usage }

    var body: some View {
        VStack(spacing: 6) {
            header
            switch viewModel.agentsMode {
            case .now: AgentsNowView(viewModel: viewModel)
            case .usage: AgentUsageView(usage: usage, range: viewModel.usageRange)
            case .activity: AgentActivityMapView(usage: usage, hovered: $hoveredDay)
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
            case .activity:
                if let day = hoveredDay, let date = day.date {
                    Text("\(AgentUsageFormat.day(date)), \(day.tokens == 0 ? "no use" : AgentUsageFormat.tokens(day.tokens) + " tokens")")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
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
                    ForEach(tasks.prefix(limits.count > 2 ? 1 : 2)) { AgentTaskRow(task: $0) }
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

/// One running task: its project, the agent and model, and how long it has run.
struct AgentTaskRow: View {
    let task: AgentTask

    var body: some View {
        HStack(spacing: 10) {
            Glyph(systemName: "sparkles", tint: Theme.Tint.working)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.project)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                Text(task.subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ElapsedText(since: task.startedAt, tint: Theme.Tint.working)
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }
}

/// Hover while an agent works: up to two tasks, each with its project, agent, model, and time.
struct AgentPeekView: View {
    let agents: AgentActivity

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            ForEach(agents.liveTasks.prefix(2)) { AgentTaskRow(task: $0) }
        }
        .frame(maxHeight: .infinity)
    }
}

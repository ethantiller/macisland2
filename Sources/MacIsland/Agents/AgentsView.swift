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

/// The Agents module: what the agents are working on now. Read from the logs Claude Code and Codex keep in the home folder.
struct AgentsView: View {
    let viewModel: IslandViewModel

    var body: some View {
        let tasks = viewModel.agents.liveTasks
        Group {
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
                    ForEach(tasks.prefix(3)) { AgentTaskRow(task: $0) }
                    Spacer(minLength: 0)
                }
            }
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

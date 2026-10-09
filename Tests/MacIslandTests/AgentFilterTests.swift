import Testing

@testable import MacIsland

/// The Stats dropdown says which tool it counts, and the map is orange only for Claude Code.
struct AgentFilterTests {
    @Test func theDropdownNamesWhatItCounts() {
        #expect(StatsFilter.allCases.map(\.title) == ["All", "Claude Code", "Codex"])
        #expect(StatsFilter.allCases.map(\.agent) == [nil, .claudeCode, .codex])
        #expect(StatsFilter.allCases.allSatisfy { StatsFilter(agent: $0.agent) == $0 })
    }

    @Test func claudesOrangeStepsMatchTheWhiteOnes() {
        #expect(Theme.Mark.claudeActivitySteps.count == Theme.Palette.activitySteps.count)
    }
}

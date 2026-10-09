import Foundation
import Testing

@testable import MacIsland

/// Agents is a tool in the Tools grid while AI Agents is on, and opens its module.
@MainActor
struct AgentsToolTests {
    private func makeSettings() -> AppSettings {
        let suite = "MacIslandAgentsTool.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    @Test func agentsIsABuiltInToolOutsideTheNine() {
        #expect(ToolID(rawValue: "agents") == .agents && ToolID.agents.isBuiltIn && ToolID.agents.shortcutID == nil)
        #expect(!ToolID.allCases.contains(.agents) && ToolID.allCases.count == 9)
    }

    @Test func theToolIsThereOnlyWhileTheFeatureIsOn() {
        let settings = makeSettings()
        settings.setOn(.agents, false)
        #expect(!settings.allTools.contains(.agents) && !settings.isKnown(.agents))
        settings.setOn(.agents, true)
        #expect(settings.allTools == ToolID.allCases + [.agents] && settings.isKnown(.agents))
    }

    @Test func itSitsBeforeTheirOwnToolsAndKeepsItsPinAcrossASwitch() {
        let settings = makeSettings()
        settings.setOn(.agents, true)
        settings.saveShortcutTool(ShortcutTool(shortcut: "Wind Down", title: "Wind Down"))
        #expect(settings.allTools[ToolID.allCases.count] == .agents)
        settings.replacePinned([.agents, .keepAwake])
        #expect(settings.visiblePinned.first == .agents)
        settings.setOn(.agents, false)
        #expect(!settings.visiblePinned.contains(.agents))
        settings.setOn(.agents, true)
        #expect(settings.visiblePinned.first == .agents, "switching it back on returns it to its place")
    }

    @Test func theGridGrowsToThreeRowsOnlyWhenTheToolsNeedIt() {
        let settings = makeSettings()
        settings.setOn(.agents, false)
        #expect(settings.toolsGridRows == 2)
        settings.saveShortcutTool(ShortcutTool(shortcut: "One", title: "One"))
        settings.saveShortcutTool(ShortcutTool(shortcut: "Two", title: "Two"))
        #expect(settings.toolsGridRows == 2, "nine, two of their own, and Less fill two rows")
        settings.setOn(.agents, true)
        #expect(settings.toolsGridRows == 3)
        #expect(Theme.Metrics.toolsGridHeight(rows: 2) == 2 * Theme.Metrics.toolsRowHeight + 10)
        #expect(Theme.Metrics.toolsGridHeight(rows: 3) == 3 * Theme.Metrics.toolsRowHeight + 20)
        #expect(Theme.Metrics.toolsGridHeight(rows: 3) <= Theme.Metrics.homeMaxContentHeight)
    }

    @Test func pressingItOpensTheAgentsModule() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setOn(.agents, true)
        let item = ToolCatalog(viewModel: viewModel).item(for: .agents)
        #expect(item.title == "Agents" && item.systemImage == "sparkles" && item.isAvailable)
        item.action()
        #expect(viewModel.selectedTab == .agents && viewModel.presentation == .expanded)
    }
}

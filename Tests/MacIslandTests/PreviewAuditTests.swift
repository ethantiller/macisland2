import Foundation
import Testing

@testable import MacIsland

/// Every Features row, in every view it lists, must show the feature it is about: the audit behind "Peek previews show what was picked".
@MainActor
struct PreviewAuditTests {
    private func makePreview() async -> (preview: IslandPreviewModel, live: IslandViewModel) {
        let live = TestSupport.makeViewModel()
        for feature in Feature.allCases where feature.isBuilt { live.settings.setOn(feature, true) }
        let preview = IslandPreviewModel(live: live.features)
        preview.viewModel.geometry = live.geometry
        // Weather arrives from a stubbed forecast, a moment after it is asked for.
        for _ in 0..<40 where preview.viewModel.weather.conditions == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return (preview, live)
    }

    /// Whether the island shows `feature`, in the way the context asked.
    private func isShown(_ feature: Feature, _ context: PreviewContext, by viewModel: IslandViewModel) -> Bool {
        let presentation = viewModel.presentation
        switch feature {
        case .music:
            switch context.presentation {
            case .expanded: return viewModel.selectedTab == .media && presentation == .expanded
            case .peek: return viewModel.peekActivity == .media
            default: return viewModel.compactActivity == .media
            }
        case .weather:
            switch context.presentation {
            case .peek: return viewModel.peekActivity == .none && viewModel.weather.conditions != nil
            default: return viewModel.showsStripWeather && presentation == .expanded
            }
        case .clipboard: return viewModel.selectedTab == .shelf && viewModel.shelfMode == .clipboard
        case .downloads: return viewModel.selectedTab == .shelf && viewModel.shelfMode == .downloads
        case .system:
            return viewModel.homeLayout.widgets.contains { $0.widget == .builtIn(.system) } && viewModel.selectedTab == .home
        case .agents:
            switch context.presentation {
            case .expanded: return viewModel.selectedTab == .agents
            case .peek: return viewModel.peekActivity == .agent
            case .compact: return viewModel.compactActivity == .agent
            default: return viewModel.alert != nil || viewModel.banner != nil
            }
        case .volumeHUD: return !viewModel.levels.isEmpty
        case .calendar:
            return context.presentation == .expanded
                ? viewModel.selectedTab == .home : (viewModel.alert != nil || viewModel.banner != nil)
        case .chooseActivity: return viewModel.choosableActivities.count >= 2 && presentation == .peek
        case .mixer: return viewModel.showsMediaOutputs && viewModel.selectedTab == .media
        case .notifications: return viewModel.alert != nil || viewModel.banner != nil
        case .clock: return viewModel.selectedTab == .clock
        case .reminders: return viewModel.selectedTab == .reminders
        case .tools: return viewModel.selectedTab == .tools
        case .notes: return viewModel.selectedTab == .notes
        case .shelf: return presentation == .compact
        }
    }

    @Test func everyRowShowsItsFeatureInEveryViewItLists() async {
        let (preview, _) = await makePreview()
        defer { preview.stop() }
        for feature in Feature.allCases where feature.isBuilt {
            for context in feature.previewContexts {
                preview.show(context, animated: false)
                #expect(isShown(feature, context, by: preview.viewModel), "\(feature) in \(context.presentation)")
            }
        }
    }

    @Test func choosingARowKeepsTheViewYouAreOnWhenTheFeatureShowsThere() async {
        let (preview, _) = await makePreview()
        defer { preview.stop() }
        for feature in Feature.allCases where feature.isBuilt {
            for presentation in feature.previewContexts.map(\.presentation) {
                preview.show(PreviewContext(presentation: presentation), animated: false)
                let next = feature.previewContext(from: preview.context)
                #expect(next?.presentation == presentation, "\(feature) on \(presentation)")
            }
        }
    }

    @Test func aFeatureNotListedInTheCurrentViewFallsBackToItsDefault() async {
        let (preview, _) = await makePreview()
        defer { preview.stop() }
        preview.show(PreviewContext(presentation: .expanded, tab: .home), animated: false)
        #expect(Feature.clipboard.previewContext(from: preview.context)?.presentation == .expanded)
        #expect(Feature.weather.previewContext(from: preview.context)?.presentation == .expanded)
        #expect(Feature.shelf.previewContext(from: preview.context)?.presentation == .compact)
    }

    @Test func musicOutranksAnAgentOnTheClosedIsland() async {
        let (preview, _) = await makePreview()
        defer { preview.stop() }
        preview.show(PreviewContext(presentation: .compact), animated: false)
        #expect(preview.viewModel.compactActivity == .media, "music leads, with the sample agent also working")
        #expect(preview.viewModel.compactPair?.trailing == .agent)
    }
}

/// Clicking Claude Code or Codex in the AI Agents options previews that tool alone, in whichever view the preview is on.
@MainActor
struct AgentPreviewTests {
    private func make() -> IslandPreviewModel {
        let live = TestSupport.makeViewModel()
        live.settings.setOn(.agents, true)
        let preview = IslandPreviewModel(live: live.features)
        preview.viewModel.geometry = live.geometry
        return preview
    }

    @Test func eachViewShowsOnlyTheToolThatWasChosen() {
        let preview = make()
        defer { preview.stop() }
        for agent in AgentKind.allCases {
            for presentation in [PreviewPresentation.compact, .peek, .banner, .expanded] {
                preview.show(
                    AgentsOptions.previewContext(for: agent, from: PreviewContext(presentation: presentation)), animated: false)
                let viewModel = preview.viewModel
                #expect(viewModel.agents.liveTasks.map(\.agent) == [agent], "\(agent) in \(presentation)")
                switch presentation {
                case .compact: #expect(viewModel.compactActivity == .agent)
                case .peek: #expect(viewModel.peekActivity == .agent)
                case .banner: #expect(viewModel.banner?.agent == agent, "its own Done notice")
                default:
                    #expect(viewModel.selectedTab == .agents && viewModel.agentsMode == .stats)
                    #expect(viewModel.statsAgent == agent, "Stats filtered to it")
                }
            }
        }
    }

    @Test func theMenuBarViewFallsBackToExpanded() {
        let context = AgentsOptions.previewContext(for: .codex, from: PreviewContext(presentation: .menuBar))
        #expect(context.presentation == .expanded && context.agent == .codex)
    }

    @Test func showingBothAgainBringsBackBothTasks() {
        let preview = make()
        defer { preview.stop() }
        preview.show(AgentsOptions.previewContext(for: .codex, from: PreviewContext(presentation: .peek)), animated: false)
        #expect(preview.viewModel.agents.liveTasks.count == 1)
        preview.show(PreviewContext(presentation: .peek, lead: .activity("agent")), animated: false)
        #expect(Set(preview.viewModel.agents.liveTasks.map(\.agent)) == [.claudeCode, .codex])
        #expect(preview.viewModel.statsAgent == nil)
    }

    @Test func theSampleUsageHasBothToolsOnDifferentDays() {
        let snapshot = PreviewSamples.usageSnapshot()
        let claude = Set(snapshot.buckets.filter { $0.agent == .claudeCode }.map(\.day))
        let codex = Set(snapshot.buckets.filter { $0.agent == .codex }.map(\.day))
        #expect(!claude.isEmpty && !codex.isEmpty && !codex.isSubset(of: claude))
        #expect(snapshot.limit(.codex, .session) != nil && !snapshot.sessions.isEmpty && !snapshot.hours.isEmpty)
    }
}

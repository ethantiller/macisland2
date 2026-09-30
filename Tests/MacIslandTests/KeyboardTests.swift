import Testing

@testable import MacIsland

@MainActor
struct KeyboardTests {
    @Test func hotkeyOpensAndPinsThenCloses() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.toggleFromKeyboard()
        #expect(viewModel.state == .expanded && viewModel.isPinnedOpen)

        // The pointer never being over the island doesn't close a pinned island.
        viewModel.setHovering(false)
        #expect(viewModel.state == .expanded)

        viewModel.toggleFromKeyboard()
        #expect(viewModel.state == .compact && !viewModel.isPinnedOpen)
    }

    @Test func hoveringTakesOverFromThePin() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.toggleFromKeyboard()
        viewModel.setHovering(true)
        #expect(!viewModel.isPinnedOpen)
    }

    @Test func arrowsMoveBetweenTabsWithoutWrapping() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.selectedTab = .home
        viewModel.selectAdjacentTab(-1)
        #expect(viewModel.selectedTab == .home)
        viewModel.selectAdjacentTab(1)
        #expect(viewModel.selectedTab == .media)
        viewModel.selectAdjacentTab(1)
        viewModel.selectAdjacentTab(1)
        viewModel.selectAdjacentTab(1)
        viewModel.selectAdjacentTab(1)
        #expect(viewModel.selectedTab == .tools)
    }

    @Test func bannerTakesOverFromThePin() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.toggleFromKeyboard()
        viewModel.showBanner(IslandBanner(systemImage: "bolt", tint: Theme.Tint.neutral, title: "T", detail: "D"))
        #expect(!viewModel.isPinnedOpen && viewModel.state == .compact)
    }
}

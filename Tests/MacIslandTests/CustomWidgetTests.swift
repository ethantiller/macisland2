import Foundation
import Testing

@testable import MacIsland

private func shortcut(_ name: String = "Battery Health", showsResult: Bool = true) -> CustomWidget {
    CustomWidget(title: "Health", systemImage: "heart", source: .shortcut(name: name, showsResult: showsResult))
}

private func web(_ address: String = "https://api.example.com/price", path: String? = "data.0.price") -> CustomWidget {
    CustomWidget(
        title: "Price", systemImage: "chart.line.uptrend.xyaxis", source: .web(url: URL(string: address)!, path: path))
}

struct WebValueTests {
    private let json = Data(#"{"data":[{"price":123.5,"name":"Acme","up":true}],"count":3,"ok":false}"#.utf8)

    @Test func aPathPicksAValueOutOfJSON() {
        #expect(WebValue.extract(json, path: "data.0.price") == "123.5")
        #expect(WebValue.extract(json, path: "data.0.name") == "Acme")
        #expect(WebValue.extract(json, path: "count") == "3")
        #expect(WebValue.extract(json, path: "data.0.up") == "Yes")
        #expect(WebValue.extract(json, path: "ok") == "No")
    }

    @Test func aMissingPathOrANonValueIsNil() {
        #expect(WebValue.extract(json, path: "data.1.price") == nil)
        #expect(WebValue.extract(json, path: "nope") == nil)
        #expect(WebValue.extract(json, path: "data") == nil, "a list isn't a value")
        #expect(WebValue.extract(Data("not json".utf8), path: "a") == nil)
    }

    @Test func withoutAPathItIsTheFirstLineOfText() {
        #expect(WebValue.extract(Data("\n  72°F and sunny  \nmore".utf8), path: nil) == "72°F and sunny")
        #expect(WebValue.extract(Data("   \n".utf8), path: "") == nil)
        let long = String(repeating: "x", count: 200)
        #expect(WebValue.extract(Data(long.utf8), path: nil)?.count == WebValue.maxLength)
    }
}

struct CustomWidgetModelTests {
    @Test func aWidgetNeedsANameARealSymbolAndAWellFormedSource() {
        #expect(shortcut().isValid)
        var noName = shortcut()
        noName.title = "  "
        #expect(!noName.isValid)
        var badSymbol = shortcut()
        badSymbol.systemImage = "definitely.not.a.symbol"
        #expect(!badSymbol.isValid)
        #expect(web().isValid)
        #expect(!web("http://api.example.com").isValid, "https only")
        #expect(!web("ftp://example.com").isValid)
        #expect(!CustomWidget(title: "F", systemImage: "folder", source: .folder(path: "relative")).isValid)
        #expect(CustomWidget(title: "F", systemImage: "folder", source: .folder(path: "/Users/me/Downloads")).isValid)
    }

    @Test func aDescriptorSaysWhatItReadsAndWhenItRefreshes() {
        let button = shortcut(showsResult: false).descriptor
        #expect(button.refresh == .onTap)
        #expect(button.tap == .runShortcut)
        let value = web().descriptor
        #expect(value.refresh == .onAppear(maxAge: .seconds(15 * 60)))
        #expect(value.source == .web)
        #expect(value.tint == .working)
        #expect(value.sizes == [GridSize(1, 1), GridSize(2, 1), GridSize(3, 1)] && value.defaultSize == GridSize(2, 1))
    }

    @Test func aWidgetRoundTripsThroughJSON() throws {
        let widgets = [
            shortcut(), web(),
            CustomWidget(title: "F", systemImage: "folder", source: .folder(path: "/tmp")),
            CustomWidget(title: "C", systemImage: "terminal", source: .command(path: "/tmp/run.sh")),
        ]
        let data = try JSONEncoder().encode(widgets)
        #expect(try JSONDecoder().decode([CustomWidget].self, from: data) == widgets)
    }
}

@MainActor
struct CustomWidgetValuesTests {
    private func makeValues(
        _ fetcher: StubWidgetFetcher, clock: @escaping () -> Date = Date.init
    ) -> CustomWidgetValues {
        CustomWidgetValues(fetcher: fetcher, now: clock)
    }

    @Test func aValueOlderThanItsLimitIsFetchedAgain() async throws {
        let fetcher = StubWidgetFetcher()
        let values = makeValues(fetcher, clock: { Date().addingTimeInterval(60 * 60) })
        let widget = web()
        // The first fetch stamps the value "now"; the clock reads an hour later, past the 15-minute limit.
        try await #require(values.refresh(widget)).value
        #expect(fetcher.calls == 1)
        values.refreshIfStale(widget)
        for _ in 0..<100 where fetcher.calls < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(fetcher.calls == 2)
    }

    @Test func aFreshValueIsNotFetchedAgain() async throws {
        let fetcher = StubWidgetFetcher()
        let values = makeValues(fetcher)
        let widget = web()
        try await #require(values.refresh(widget)).value
        values.refreshIfStale(widget)
        values.refreshIfStale(widget)
        #expect(fetcher.calls == 1)
    }

    @Test func aWidgetNeverHasTwoFetchesAtOnce() async throws {
        let fetcher = StubWidgetFetcher()
        var release: AsyncStream<Void>.Continuation!
        fetcher.gate = AsyncStream { release = $0 }
        let values = makeValues(fetcher)
        let widget = web()

        let first = try #require(values.refresh(widget))
        #expect(values.state(for: widget.id) == .updating)
        #expect(values.refresh(widget) == nil, "already updating")
        values.refreshIfStale(widget)
        for _ in 0..<50 where fetcher.calls == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(fetcher.calls == 1)
        release.yield()
        await first.value
        #expect(values.state(for: widget.id) == .idle)
    }

    @Test func aFailureIsRememberedAndTheNextTryRuns() async throws {
        let fetcher = StubWidgetFetcher()
        fetcher.failure = .badResponse
        let values = makeValues(fetcher)
        let widget = web()
        await values.refresh(widget)?.value
        #expect(values.state(for: widget.id) == .failed(WidgetFetchError.badResponse.localizedDescription))
        #expect(values.value(for: widget.id) == nil)
        fetcher.failure = nil
        await values.refresh(widget)?.value
        #expect(values.state(for: widget.id) == .idle)
        #expect(values.value(for: widget.id)?.text == "42")
    }

    @Test func aButtonNeverFetches() {
        let fetcher = StubWidgetFetcher()
        let values = makeValues(fetcher)
        values.refreshIfStale(shortcut(showsResult: false))
        #expect(fetcher.calls == 0)
    }
}

struct BoundedProcessTests {
    private func script(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macisland-test-\(UUID().uuidString).sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func aProgramRunsAndItsOutputIsRead() throws {
        let url = try script("echo hello; echo world")
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try BoundedProcess.run(executable: url, timeout: 5, outputLimit: 4096)
        #expect(output.text == "hello\nworld\n" && output.status == 0 && !output.timedOut)
    }

    @Test func aSlowProgramIsStopped() throws {
        let url = try script("sleep 30")
        defer { try? FileManager.default.removeItem(at: url) }
        let started = Date()
        let output = try BoundedProcess.run(executable: url, timeout: 0.5, outputLimit: 4096)
        #expect(output.timedOut)
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func aTalkativeProgramIsCutOff() throws {
        let url = try script("yes abcdefghij")
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try BoundedProcess.run(executable: url, timeout: 5, outputLimit: 100)
        #expect(output.text.utf8.count == 100)
    }

    @Test func itGetsAMinimalEnvironmentAndNoInput() throws {
        let url = try script(#"echo "$PATH"; echo "${SECRET_TOKEN:-none}"; cat"#)
        defer { try? FileManager.default.removeItem(at: url) }
        setenv("SECRET_TOKEN", "leak", 1)
        defer { unsetenv("SECRET_TOKEN") }
        let output = try BoundedProcess.run(executable: url, timeout: 5, outputLimit: 4096)
        #expect(output.text == "/usr/bin:/bin:/usr/sbin:/sbin\nnone\n")
    }

    @Test func aFileThatCantRunIsRefused() {
        #expect(throws: BoundedProcess.RunError.notExecutable) {
            try BoundedProcess.run(executable: URL(fileURLWithPath: "/nonexistent/thing"), timeout: 1, outputLimit: 10)
        }
    }
}

@MainActor
struct CustomWidgetSettingsTests {
    private func makeSettings() -> (AppSettings, UserDefaults) {
        let name = "MacIslandCustom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (AppSettings(defaults: defaults), defaults)
    }

    @Test func customWidgetsPersistAndLiveInTheCatalog() {
        let (settings, defaults) = makeSettings()
        let widget = web()
        #expect(settings.saveCustomWidget(widget))
        #expect(settings.widgetDescriptor(for: .custom(widget.id))?.title == "Price")
        #expect(AppSettings(defaults: defaults).customWidgets == [widget])
        #expect(!settings.saveCustomWidget(web("http://insecure.example.com")))
    }

    @Test func aCustomWidgetOnHomeSurvivesRelaunchAndFitsTheRules() {
        let (settings, defaults) = makeSettings()
        let widget = shortcut()
        settings.saveCustomWidget(widget)
        var layout = settings.homeLayout
        layout.widgets[1] = WidgetPlacement(widget: .custom(widget.id), size: GridSize(2, 1))
        // Today | Custom takes the place of Music.
        settings.setHomeLayout(layout)
        #expect(settings.homeLayout.widgets[1].widget == .custom(widget.id))
        #expect(AppSettings(defaults: defaults).homeLayout.widgets[1].widget == .custom(widget.id))
    }

    @Test func deletingAWidgetTakesItOffHomeAndOutOfNotShown() {
        let (settings, _) = makeSettings()
        let widget = shortcut()
        settings.saveCustomWidget(widget)
        settings.setHomeLayout(
            HomeLayout(widgets: [
                WidgetPlacement(widget: .builtIn(.today), size: GridSize(3, 1)),
                WidgetPlacement(widget: .custom(widget.id), size: GridSize(2, 1)),
            ])
        )
        settings.removeCustomWidget(widget.id)
        #expect(settings.customWidgets.isEmpty)
        #expect(settings.homeLayout.widgets.allSatisfy { $0.widget != .custom(widget.id) })
        #expect(settings.homeLayout.hidden.allSatisfy { $0.widget != .custom(widget.id) })
    }

    @Test func aStoredLayoutWithAnUnknownCustomWidgetIsRepaired() {
        let (settings, defaults) = makeSettings()
        var layout = HomeLayout.default
        layout.widgets[1] = WidgetPlacement(widget: .custom(UUID()), size: GridSize(3, 1))
        defaults.set(try? JSONEncoder().encode(layout), forKey: "home.layout")
        _ = settings
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.homeLayout.widgets.allSatisfy { if case .custom = $0.widget { false } else { true } })
    }

    @Test func homeRendersACustomWidgetFromItsValue() async throws {
        let viewModel = TestSupport.makeViewModel()
        let widget = web()
        viewModel.settings.saveCustomWidget(widget)
        try await #require(viewModel.widgets.refresh(widget)).value
        #expect(viewModel.widgets.value(for: widget.id)?.text == "42")
    }
}

import AppKit
import Foundation
import Testing

@testable import MacIsland

@MainActor
struct URLCommandTests {
    private func parse(_ text: String) -> URLCommand? { URLCommand.parse(URL(string: text)!) }

    @Test func parsesEachCommand() throws {
        #expect(parse("macisland://timer?minutes=5") == .timer(minutes: 5))
        #expect(parse("macisland://stopwatch") == .stopwatch)
        #expect(parse("macisland://pomodoro") == .pomodoro)
        #expect(parse("macisland://palette") == nil, "the palette is gone")
        #expect(parse("macisland://open?module=notes") == .open(.notes))
        #expect(
            parse("macisland://banner?title=Hi&detail=There&symbol=bell.fill")
                == .banner(title: "Hi", detail: "There", symbol: "bell.fill"))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let encoded = file.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        #expect(parse("macisland://shelf/add?path=\(encoded)") == .addToShelf(file.standardizedFileURL))
    }

    @Test func enforcesTheLimits() {
        #expect(parse("macisland://timer?minutes=0") == nil)
        #expect(parse("macisland://timer?minutes=99999") == nil)
        #expect(parse("macisland://timer") == nil)
        #expect(parse("macisland://open?module=agents") == nil)
        #expect(parse("macisland://open?module=nope") == nil)
        #expect(parse("macisland://shelf/add?path=/no/such/file") == nil)
        #expect(parse("macisland://shelf/add?path=relative.txt") == nil)
        #expect(parse("macisland://banner") == nil)
        #expect(parse("macisland://frobnicate") == nil)
        #expect(parse("https://timer?minutes=5") == nil)

        let longTitle = String(repeating: "t", count: 200), longDetail = String(repeating: "d", count: 200)
        guard
            case .banner(let title, let detail, let symbol) = parse(
                "macisland://banner?title=\(longTitle)&detail=\(longDetail)&symbol=Not%20A%20Symbol!")
        else {
            Issue.record("expected a banner")
            return
        }
        #expect(title.count == 60 && detail?.count == 80 && symbol == nil)
    }

    @Test func bannersAreRateLimited() {
        let viewModel = TestSupport.makeViewModel()
        var now = Date(timeIntervalSince1970: 5_000)
        let runner = URLCommandRunner(viewModel: viewModel, now: { now })
        runner.run(.banner(title: "First", detail: nil, symbol: nil))
        #expect(viewModel.banner?.title == "First")
        now += 1
        runner.run(.banner(title: "Second", detail: nil, symbol: nil))
        #expect(viewModel.banner?.title == "First")
        now += 1.5
        runner.run(.banner(title: "Third", detail: nil, symbol: "not.a.real.symbol.name"))
        #expect(viewModel.banner?.title == "Third" && viewModel.banner?.systemImage == "bell.fill")
        #expect(viewModel.banner?.actions.isEmpty == true)
    }

    @Test func commandsDriveTheApp() {
        let viewModel = TestSupport.makeViewModel()
        let runner = URLCommandRunner(viewModel: viewModel)
        runner.handle([
            URL(string: "macisland://timer?minutes=3")!, URL(string: "macisland://open?module=tools")!,
        ])
        #expect(viewModel.timer.duration == 180 && viewModel.selectedTab == .tools)
        runner.run(.stopwatch)
        #expect(viewModel.stopwatch.isRunning)
        runner.run(.pomodoro)
        #expect(viewModel.pomodoro.isActive)
    }
}

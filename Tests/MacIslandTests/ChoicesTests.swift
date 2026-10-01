import Foundation
import Testing

@testable import MacIsland

@MainActor
struct ShelfChoicesTests {
    private func makeDefaults() -> UserDefaults {
        let name = "MacIslandShelfChoices.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeFile(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    @Test func filesAreSweptAfterADayOrAWeekAndNeverByDefault() {
        var time = Date(timeIntervalSince1970: 2_000_000)
        let shelf = ShelfModel(defaults: makeDefaults(), now: { time })
        let old = makeFile("old.txt")
        let recent = makeFile("recent.txt")
        defer { [old, recent].forEach { try? FileManager.default.removeItem(at: $0) } }

        shelf.add([old])
        time += 2 * 24 * 3600
        shelf.add([recent])

        #expect(shelf.sweep(.never) == 0)
        #expect(shelf.items == [old, recent])

        time += 3600
        #expect(shelf.sweep(.day) == 1, "the two-day-old file goes, the hour-old one stays")
        #expect(shelf.items == [recent])
        #expect(FileManager.default.fileExists(atPath: old.path), "only the reference is removed")

        time += 8 * 24 * 3600
        #expect(shelf.sweep(.week) == 1)
        #expect(shelf.items.isEmpty)
    }

    @Test func aFileFromBeforeDatesWereKeptCountsFromTheFirstLaunchAfter() {
        let defaults = makeDefaults()
        let file = makeFile("before.txt")
        defer { try? FileManager.default.removeItem(at: file) }
        defaults.set([file.path], forKey: "shelf.paths")

        let launch = Date(timeIntervalSince1970: 3_000_000)
        let shelf = ShelfModel(defaults: defaults, now: { launch })
        #expect(shelf.addedAt(file) == launch)
        // The date was written, so a later launch doesn't move it.
        let later = ShelfModel(defaults: defaults, now: { launch.addingTimeInterval(99_999) })
        #expect(later.addedAt(file) == launch)
        #expect(later.sweep(.day) == 1)
    }

    @Test func aSweepUsesTheSettingWhenTheShelfAppears() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.shelfRetention = .day
        viewModel.sweepShelf()  // nothing to sweep, and nothing breaks
        #expect(viewModel.shelf.items.isEmpty)
    }

    @Test func choicesPersistWithSensibleDefaults() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.dragTarget == .shelfAndAirDrop && settings.addsScreenshots && settings.showsMusicCompact)
        #expect(settings.shelfRetention == .never && settings.clipboardLimit == 10 && settings.shelfMode == .files)
        settings.dragTarget = .shelfOnly
        settings.addsScreenshots = false
        settings.shelfRetention = .week
        settings.clipboardLimit = 25
        settings.shelfMode = .clipboard
        settings.showsMusicCompact = false
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.dragTarget == .shelfOnly && !reloaded.addsScreenshots && reloaded.shelfRetention == .week)
        #expect(reloaded.clipboardLimit == 25 && reloaded.shelfMode == .clipboard && !reloaded.showsMusicCompact)
        reloaded.dragTarget = .airDropOnly
        #expect(AppSettings(defaults: defaults).dragTarget == .airDropOnly)
    }

    @Test func aClipboardLimitOutsideTheChoicesFallsBack() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: "clipboardLimit")
        #expect(AppSettings(defaults: defaults).clipboardLimit == 10)
    }

    @Test func theShelfOpensOnTheModeItWasLeftIn() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.setShelfMode(.clipboard)
        #expect(viewModel.settings.shelfMode == .clipboard)
        let next = IslandViewModel(features: viewModel.features)
        #expect(next.shelfMode == .clipboard)
        // A drop always shows Files, without forgetting the choice.
        next.setDropTargeted(true)
        #expect(next.shelfMode == .files)
        #expect(next.settings.shelfMode == .clipboard)
    }
}

@MainActor
struct ClipboardLimitTests {
    @Test func aLimitKeepsThatManyAndOffKeepsNoneAndStopsWatching() {
        let history = ClipboardHistory()
        history.setCapacity(25)
        #expect(history.isWatching)
        for index in 0..<40 { history.record(.text("copy \(index)")) }
        #expect(history.entries.count == 25)

        history.setCapacity(10)
        #expect(history.entries.count == 10, "a smaller limit trims what is kept")

        history.setCapacity(0)
        #expect(!history.isWatching, "off removes the standing timer")
        #expect(history.entries.isEmpty)
        history.record(.text("ignored"))
        #expect(history.entries.isEmpty)
        history.start()
        #expect(!history.isWatching, "off stays off")

        history.setCapacity(10)
        #expect(history.isWatching)
        history.stop()
    }

    @Test func anUnknownLimitIsTheDefault() {
        let history = ClipboardHistory()
        history.setCapacity(7, running: false)
        #expect(history.capacity == ClipboardHistory.limit)
    }
}

@MainActor
struct DragAndMusicChoicesTests {
    @Test func doNothingLeavesTheIslandAloneWhileAFileIsDragged() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.dragTarget = .nothing
        viewModel.setFileDragActive(true)
        #expect(!viewModel.isFileDragActive && !viewModel.showsDragTarget)
    }

    @Test func shelfOnlyStillGrowsTheTarget() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.dragTarget = .shelfOnly
        viewModel.setFileDragActive(true)
        #expect(viewModel.showsDragTarget)
        viewModel.setFileDragActive(false)
    }

    @Test func airDropOnlyStillGrowsTheTargetOnlyDuringAFileDrag() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.dragTarget = .airDropOnly
        let resting = viewModel.size
        viewModel.setFileDragActive(true)
        #expect(viewModel.showsDragTarget)
        #expect(viewModel.size.width == viewModel.geometry.compactSize.width + 2 * Theme.Metrics.dragTargetInset)
        #expect(viewModel.size.height == resting.height + Theme.Metrics.dragTargetHeight)
        viewModel.setFileDragActive(false)
        #expect(viewModel.size == resting)
    }

    @Test func dropModesRouteToTheirConfiguredDestination() {
        #expect(DropZone.destination(for: .shelfOnly, locationX: 180, width: 200) == .shelf)
        #expect(DropZone.destination(for: .airDropOnly, locationX: 20, width: 200) == .airDrop)
        #expect(DropZone.destination(for: .shelfAndAirDrop, locationX: 20, width: 200) == .shelf)
        #expect(DropZone.destination(for: .shelfAndAirDrop, locationX: 180, width: 200) == .airDrop)
    }

    @Test func musicLeavesTheCompactIslandButNotTheTab() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.nowPlaying.apply(PreviewSamples.track())
        #expect(viewModel.compactActivity == .media)
        viewModel.settings.showsMusicCompact = false
        #expect(viewModel.compactActivity == .none)
        #expect(viewModel.nowPlaying.state.hasMedia, "the Media tab and Home widget still have it")
    }

    @Test func thePreviewShowsTheChosenDropTarget() {
        let live = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.show(ShelfOptions.dragPreview)
        #expect(preview.viewModel.showsDragTarget)
        live.settings.dragTarget = .nothing
        preview.show(ShelfOptions.dragPreview)
        #expect(!preview.viewModel.showsDragTarget)
    }
}

@MainActor
struct ToolOrderTests {
    @Test func aPinnedToolMovesBeforeAnotherOrLast() {
        let settings = TestSupport.makeViewModel().settings
        let row = settings.visiblePinned
        settings.movePinned(row[3], before: row[0])
        #expect(settings.visiblePinned == [row[3], row[0], row[1], row[2], row[4], row[5]])
        settings.movePinned(row[3], before: nil)
        #expect(settings.visiblePinned == [row[0], row[1], row[2], row[4], row[5], row[3]])
    }

    @Test func aMoveThatChangesNothingWritesNothing() {
        let name = "MacIslandToolOrder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let settings = AppSettings(defaults: defaults)
        let row = settings.visiblePinned
        settings.movePinned(row[0], before: row[0])
        settings.movePinned(row[0], before: row[1])
        #expect(defaults.stringArray(forKey: "pinnedTools") == nil)
        settings.movePinned(row[1], before: row[0])
        #expect(AppSettings(defaults: defaults).visiblePinned.first == row[1])
    }

    @Test func homesQuickToolsFollowTheRowOrder() {
        let settings = TestSupport.makeViewModel().settings
        let row = settings.visiblePinned
        settings.movePinned(row[5], before: row[0])
        #expect(Array(settings.visiblePinned.prefix(4)).first == row[5])
    }
}

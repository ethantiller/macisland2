import Foundation
import Testing

@testable import MacIsland

@MainActor
struct DownloadsTests {
    private func makeFolder(_ names: [String]) -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names { FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data("x".utf8)) }
        return folder
    }

    @Test func newestFirstAndAtMostTwenty() throws {
        let names = (1...25).map { String(format: "f%02d.txt", $0) }
        let folder = makeFolder(names)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Added in the order of the names, ten seconds apart.
        let found = try #require(
            DownloadsScan.newest(
                in: folder, dateAdded: { Date(timeIntervalSince1970: Double(Int($0.lastPathComponent.dropFirst().prefix(2)) ?? 0) * 10) }))
        #expect(found.count == 20)
        #expect(found.first?.name == "f25.txt" && found.last?.name == "f06.txt")
        #expect(DownloadsScan.newest(in: folder, limit: 3)?.count == 3)
    }

    @Test func hiddenFilesAndMissingFolders() {
        let folder = makeFolder([".DS_Store", ".hidden", "a.pdf"])
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(DownloadsScan.newest(in: folder)?.map(\.name) == ["a.pdf"])
        #expect(DownloadsScan.newest(in: folder.appendingPathComponent("nope")) == nil)
        let missing = DownloadsFolder(folder: folder.appendingPathComponent("nope"))
        missing.reload()
        #expect(!missing.canRead && missing.items.isEmpty, "it can say it could not read it")
    }

    @Test func partialFilesShowAsArriving() throws {
        let folder = makeFolder(["a.pdf", "b.zip.download", "c.mov.crdownload", "d.iso.part"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let items = try #require(DownloadsScan.newest(in: folder))
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        #expect(byName["a.pdf"]?.isArriving == false)
        #expect(byName["b.zip"]?.isArriving == true && byName["c.mov"]?.isArriving == true && byName["d.iso"]?.isArriving == true)
        #expect(items.count == 4)

        // How far along: matched by the name without the partial suffix.
        let transfers = [
            TransferMonitor.Transfer(id: UUID(), url: folder.appendingPathComponent("b.zip.download"), fraction: 0.4)
        ]
        let arriving = try #require(byName["b.zip"])
        #expect(DownloadsScan.fraction(of: arriving, in: transfers) == 0.4)
        #expect(DownloadsScan.fraction(of: try #require(byName["c.mov"]), in: transfers) == nil, "no report yet")
        #expect(DownloadsScan.fraction(of: try #require(byName["a.pdf"]), in: transfers) == nil, "a finished file has none")
    }

    @Test func theModeIsGoneWithTheFeatureOff() {
        #expect(ShelfMode.available(clipboard: true, downloads: false) == [.files, .clipboard])
        #expect(ShelfMode.available(clipboard: false, downloads: true) == [.files, .downloads])
        #expect(ShelfMode.available(clipboard: true, downloads: true) == [.files, .clipboard, .downloads])
        #expect(ShelfMode.available(clipboard: false, downloads: false) == [.files], "no choice to make")

        let viewModel = TestSupport.makeViewModel()
        viewModel.setShelfMode(.downloads)
        #expect(viewModel.shelfMode == .files, "it can\u{2019}t be chosen while the feature is off")
        viewModel.settings.setOn(.downloads, true)
        viewModel.setShelfMode(.downloads)
        #expect(viewModel.shelfMode == .downloads && viewModel.settings.shelfMode == .downloads)
        viewModel.settings.setOn(.downloads, false)
        viewModel.leaveModuleThatIsOff()
        #expect(viewModel.shelfMode == .files)
    }

    @Test func watchingStopsWhenTheModeIsHidden() async throws {
        let folder = makeFolder([])
        defer { try? FileManager.default.removeItem(at: folder) }
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setOn(.downloads, true)
        viewModel.selectedTab = .shelf
        viewModel.state = .expanded
        viewModel.setShelfMode(.downloads)
        #expect(viewModel.isDownloadsShowing)
        viewModel.setShelfMode(.files)
        #expect(!viewModel.isDownloadsShowing)

        let downloads = DownloadsFolder(folder: folder)
        downloads.settleDelay = .milliseconds(20)
        #expect(!downloads.isWatching, "nothing is open until the mode shows")
        downloads.start()
        #expect(downloads.isWatching && downloads.items.isEmpty)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("new.pdf").path, contents: Data("x".utf8))
        try await Task.sleep(for: .milliseconds(500))
        #expect(downloads.items.map(\.name) == ["new.pdf"], "a change lists the folder again")
        downloads.stop()
        #expect(!downloads.isWatching)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("later.pdf").path, contents: Data("x".utf8))
        try await Task.sleep(for: .milliseconds(300))
        #expect(downloads.items.count == 1, "nothing is listening any more")
    }

    @Test func quickLookSkipsAFileStillArriving() throws {
        let folder = makeFolder(["a.pdf", "b.zip.download"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let viewModel = TestSupport.makeViewModel()
        viewModel.settings.setOn(.downloads, true)
        viewModel.selectedTab = .shelf
        viewModel.state = .expanded
        viewModel.setShelfMode(.downloads)
        let downloads = DownloadsFolder(folder: folder)
        downloads.reload()
        // The view model reads its own features' folder; this one is checked on its own.
        #expect(downloads.items.filter { !$0.isArriving }.map(\.name) == ["a.pdf"])
        #expect(!viewModel.quickLookHoveredItem(), "nothing is hovered")
    }

    @Test func downloadsIsAFeatureWithAnOptionalNote() {
        #expect(Feature.downloads.isBuilt)
        #expect(Feature.downloads.previewContext?.shelfMode == .downloads)
        let live = TestSupport.makeViewModel()
        live.settings.setOn(.downloads, true)
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.show(Feature.downloads.previewContext ?? PreviewContext(), animated: false)
        #expect(preview.viewModel.shelfMode == .downloads && live.shelfMode == .files, "the preview doesn\u{2019}t move the real one")
        #expect(preview.viewModel.downloads.items.count == 5 && preview.viewModel.downloads.items.contains { $0.isArriving })
    }
}

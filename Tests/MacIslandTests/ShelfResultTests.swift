import AppKit
import Foundation
import Testing

@testable import MacIsland

/// A job that makes a file waits for a choice: Add to Shelf, Replace, or Save to Folder. Nothing lands until then.
@MainActor
struct ShelfResultTests {
    private struct Rig {
        let tools: FileTools
        let shelf: ShelfModel
        let root: URL
        var staging: URL { root.appendingPathComponent("Staging") }
        var owned: URL { root.appendingPathComponent("Owned") }
        var source: URL { root.appendingPathComponent("Source") }
    }

    private func makeRig(trash: @escaping (URL) -> Void = { _ in }) throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Source"), withIntermediateDirectories: true)
        let suite = "MacIslandShelfResults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let shelf = ShelfModel(defaults: defaults, ownedFolder: root.appendingPathComponent("Owned"), trash: trash)
        let tools = FileTools(
            shelf: shelf, work: WorkTracker(),
            pasteboard: NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)),
            stagingRoot: root.appendingPathComponent("Staging"))
        return Rig(tools: tools, shelf: shelf, root: root)
    }

    private func makeFile(_ name: String, in directory: URL, text: String = "hello") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func waitForResults(_ tools: FileTools, count: Int = 1) async {
        for _ in 0..<300 where tools.pending.count < count { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    // MARK: Staging

    @Test func aJobWaitsInAStagingFolderAndLandsNowhere() async throws {
        let rig = try makeRig()
        let file = try makeFile("a.txt", in: rig.source)
        var announced: [String] = []
        rig.tools.onResult = { announced.append($0.verb) }
        rig.tools.zip([file])
        await waitForResults(rig.tools)

        let result = try #require(rig.tools.pending.first)
        #expect(result.verb == "Zipped" && result.name == "a.txt.zip" && result.sources == [file])
        #expect(announced == ["Zipped"])
        #expect(FileManager.default.fileExists(atPath: result.staged.path))
        #expect(result.staged.path.hasPrefix(rig.staging.path))
        // Nothing beside the original, nothing on the Shelf, nothing in the folder MacIsland owns.
        #expect(names(in: rig.source) == ["a.txt"])
        #expect(rig.shelf.items.isEmpty)
        #expect(names(in: rig.owned).isEmpty)
    }

    @Test func aFailedJobLeavesNothingBehind() async throws {
        let rig = try makeRig()
        let notAnArchive = try makeFile("fake.zip", in: rig.source, text: "not a zip")
        var failures: [String] = []
        rig.tools.onFail = { failures.append($0) }
        rig.tools.unzip(notAnArchive)
        for _ in 0..<300 where failures.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(failures.count == 1 && rig.tools.pending.isEmpty)
        #expect(names(in: rig.staging).isEmpty)
        #expect(names(in: rig.source) == ["fake.zip"])
    }

    // MARK: The three outcomes

    @Test func addToShelfMovesTheResultIntoTheFolderMacIslandOwns() async throws {
        let rig = try makeRig()
        let file = try makeFile("a.txt", in: rig.source)
        rig.shelf.add([file])
        rig.tools.zip([file])
        await waitForResults(rig.tools)
        let result = try #require(rig.tools.pending.first)

        #expect(rig.tools.addToShelf(result))
        let added = rig.owned.appendingPathComponent("a.txt.zip")
        #expect(rig.shelf.items == [file, added])
        #expect(FileManager.default.fileExists(atPath: added.path) && rig.shelf.isOwned(added))
        #expect(rig.tools.pending.isEmpty && names(in: rig.staging).isEmpty)
        #expect(names(in: rig.source) == ["a.txt"], "the original is where it was")
    }

    @Test func replaceSwapsTheEntryAndNeverTouchesTheOriginalFile() async throws {
        let rig = try makeRig()
        let first = try makeFile("a.txt", in: rig.source)
        let second = try makeFile("b.txt", in: rig.source)
        rig.shelf.add([first, second])
        rig.tools.zip([first])
        await waitForResults(rig.tools)

        let result = try #require(rig.tools.pending.first)
        #expect(rig.tools.replaceInShelf(result))
        let zipped = rig.owned.appendingPathComponent("a.txt.zip")
        #expect(rig.shelf.items == [zipped, second], "the result takes the original's place")
        #expect(names(in: rig.source) == ["a.txt", "b.txt"], "no file on disk is deleted")
        #expect(rig.tools.pending.isEmpty)
    }

    @Test func saveToFolderMovesTheResultWhereThePanelSaid() async throws {
        let rig = try makeRig()
        let file = try makeFile("a.txt", in: rig.source)
        let destinationFolder = rig.root.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        var asked: [String] = []
        rig.tools.chooseDestination = { name in
            asked.append(name)
            return destinationFolder.appendingPathComponent("Mine.zip")
        }
        var done: [String] = []
        rig.tools.onDone = { done.append($0) }
        rig.tools.zip([file])
        await waitForResults(rig.tools)

        let result = try #require(rig.tools.pending.first)
        #expect(await rig.tools.saveToFolder(result))
        #expect(asked == ["a.txt.zip"] && done == ["Saved"])
        #expect(names(in: destinationFolder) == ["Mine.zip"])
        #expect(rig.tools.pending.isEmpty && names(in: rig.staging).isEmpty)
        #expect(rig.shelf.items.isEmpty && names(in: rig.source) == ["a.txt"])
    }

    @Test func cancellingTheSavePanelKeepsTheChoiceAndDiscardLeavesNothing() async throws {
        let rig = try makeRig()
        let file = try makeFile("a.txt", in: rig.source)
        rig.tools.chooseDestination = { _ in nil }
        rig.tools.zip([file])
        await waitForResults(rig.tools)
        let result = try #require(rig.tools.pending.first)

        #expect(await rig.tools.saveToFolder(result) == false)
        #expect(rig.tools.pending == [result] && FileManager.default.fileExists(atPath: result.staged.path))

        rig.tools.discard(result)
        #expect(rig.tools.pending.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: result.staged.path))
        #expect(names(in: rig.staging).isEmpty && names(in: rig.owned).isEmpty)
        #expect(rig.shelf.items.isEmpty && names(in: rig.source) == ["a.txt"])
    }

    @Test func severalResultsWaitInTheOrderTheyWereMade() async throws {
        let rig = try makeRig()
        let first = try makeFile("a.txt", in: rig.source)
        let second = try makeFile("b.txt", in: rig.source)
        rig.tools.zip([first])
        await waitForResults(rig.tools)
        rig.tools.zip([second])
        await waitForResults(rig.tools, count: 2)
        #expect(rig.tools.pending.map(\.name) == ["a.txt.zip", "b.txt.zip"])

        rig.tools.addToShelf(rig.tools.pending[0])
        #expect(rig.tools.pending.map(\.name) == ["b.txt.zip"])
    }

    @Test func cleaningUpRemovesEveryStagingFolderAndWhatIsPending() async throws {
        let rig = try makeRig()
        let file = try makeFile("a.txt", in: rig.source)
        rig.tools.zip([file])
        await waitForResults(rig.tools)
        rig.tools.cleanUpStaging()
        #expect(rig.tools.pending.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.staging.path))
    }

    // MARK: What leaving the Shelf does to a file

    @Test func onlyAFileMacIslandOwnsGoesToTheTrashWhenItsEntryLeaves() async throws {
        var trashed: [URL] = []
        let rig = try makeRig(trash: { trashed.append($0) })
        let outside = try makeFile("mine.txt", in: rig.source)
        try FileManager.default.createDirectory(at: rig.owned, withIntermediateDirectories: true)
        let owned = try makeFile("made.zip", in: rig.owned)
        let ownedToo = try makeFile("also.zip", in: rig.owned)
        rig.shelf.add([outside, owned, ownedToo])

        rig.shelf.remove(outside)
        #expect(trashed.isEmpty, "a file saved anywhere else is never touched")
        rig.shelf.remove(owned)
        #expect(trashed == [owned])
        rig.shelf.clear()
        #expect(trashed == [owned, ownedToo])
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func replacingKeepsTheRestOfTheShelfInOrder() throws {
        let rig = try makeRig()
        let a = rig.source.appendingPathComponent("a")
        let b = rig.source.appendingPathComponent("b")
        let c = rig.source.appendingPathComponent("c")
        let result = rig.owned.appendingPathComponent("r")
        rig.shelf.add([a, b, c])
        rig.shelf.replace([b, c], with: result)
        #expect(rig.shelf.items == [a, result])
        rig.shelf.replace([a], with: result)
        #expect(rig.shelf.items == [result], "a result already there isn't added twice")
    }

    // MARK: Previews

    @Test func aPreviewIsDrawnAgainWhenTheFileOrTheSizeChanges() throws {
        let rig = try makeRig()
        let file = try makeFile("a.txt", in: rig.source)
        let before = ShelfThumbnails.key(for: file, size: 42)
        #expect(before == ShelfThumbnails.key(for: file, size: 42))
        #expect(before != ShelfThumbnails.key(for: file, size: 64))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -5_000)], ofItemAtPath: file.path)
        #expect(before != ShelfThumbnails.key(for: file, size: 42))
    }
}

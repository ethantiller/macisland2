import AppKit
import Foundation
import Testing

@testable import MacIsland

/// Presses nothing: counts the pastes it was asked for.
@MainActor
private final class StubPaster: Pasting {
    var canPaste = true
    private(set) var pastes = 0

    func paste() -> Bool {
        pastes += 1
        return true
    }
}

@MainActor
struct ClipboardSearchTests {
    private func history(_ texts: [String]) -> ClipboardHistory {
        let history = ClipboardHistory()
        // Oldest first, so the last is the newest and shows first.
        for text in texts.reversed() { history.record(.text(text)) }
        return history
    }

    private func texts(_ entries: [ClipboardEntry]) -> [String] {
        entries.compactMap { if case .text(let text) = $0.content { text } else { nil } }
    }

    @Test func everyWordHasToMatchInAnyOrder() {
        let history = history(["Hello World", "world peace", "hello again", "nothing"])
        #expect(texts(history.matches("world hello")) == ["Hello World"])
        #expect(texts(history.matches("hello")) == ["Hello World", "hello again"])
        #expect(texts(history.matches("peace world")) == ["world peace"])
        #expect(texts(history.matches("   ")).count == 4, "an empty query is everything")
        #expect(history.matches("zebra").isEmpty)
    }

    @Test func matchingIgnoresCaseAndAccents() {
        let history = history(["Caf\u{00E9} menu", "other"])
        #expect(texts(history.matches("cafe")) == ["Caf\u{00E9} menu"])
        #expect(texts(history.matches("CAFÉ")) == ["Caf\u{00E9} menu"])
        #expect(ClipboardSearch.matches("RÉSUMÉ", query: "resume"))
    }

    @Test func rangesCoverEachMatchedWord() {
        let text = "foo and bar and foo"
        let found = ClipboardSearch.ranges(of: "foo bar", in: text).map { String(text[$0]) }
        #expect(found == ["foo", "bar", "foo"])
        // Overlapping matches are one.
        let joined = ClipboardSearch.ranges(of: "ab bc", in: "xabcx").map { String(("xabcx")[$0]) }
        #expect(joined == ["abc"])
        #expect(ClipboardSearch.ranges(of: "", in: text).isEmpty)

        let parts = ClipboardSearch.segments(of: "and", in: text)
        #expect(parts.map(\.text).joined() == text, "the runs make up the text")
        #expect(parts.filter(\.isMatch).map(\.text) == ["and", "and"])
    }

    @Test func imagesShowOnlyWithoutAQuery() {
        let history = ClipboardHistory()
        history.record(.image(NSImage(size: NSSize(width: 4, height: 4))))
        history.record(.text("hello"))
        #expect(history.matches("").count == 2)
        #expect(history.matches("hello").count == 1)
        #expect(history.matches("image").isEmpty)
    }

    // MARK: Paste

    private func makeViewModel(_ texts: [String], paster: StubPaster) -> IslandViewModel {
        let viewModel = TestSupport.makeViewModel()
        viewModel.paster = paster
        viewModel.pasteDelay = .zero
        viewModel.pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        for text in texts.reversed() { viewModel.clipboard.record(.text(text)) }
        viewModel.select(.shelf)
        viewModel.setShelfMode(.clipboard)
        viewModel.open()
        return viewModel
    }

    private func pasted(_ viewModel: IslandViewModel) -> String? {
        viewModel.pasteboard.string(forType: .string)
    }

    @Test func commandThreePastesTheThirdShown() async {
        let paster = StubPaster()
        let viewModel = makeViewModel(["one", "two", "three", "four"], paster: paster)
        #expect(viewModel.pasteClipboardShortcut(3))
        await viewModel.pasteTask?.value
        #expect(pasted(viewModel) == "three" && paster.pastes == 1)
        #expect(viewModel.state == .compact, "the island folds")
    }

    @Test func theDigitCountsWhatIsShownAfterTheFilter() async {
        let paster = StubPaster()
        let viewModel = makeViewModel(["apple pie", "banana", "apple tart", "cherry"], paster: paster)
        viewModel.clipboardQuery = "apple"
        #expect(viewModel.pasteClipboardShortcut(2))
        await viewModel.pasteTask?.value
        #expect(pasted(viewModel) == "apple tart")
        #expect(viewModel.clipboardQuery.isEmpty, "the search is done with")
    }

    @Test func returnPastesTheFirstMatch() async {
        let paster = StubPaster()
        let viewModel = makeViewModel(["apple pie", "banana", "apple tart"], paster: paster)
        viewModel.clipboardQuery = "tart"
        #expect(viewModel.pasteFirstClipboardMatch())
        await viewModel.pasteTask?.value
        #expect(pasted(viewModel) == "apple tart" && paster.pastes == 1)
    }

    @Test func aDigitPastTheListDoesNothing() {
        let paster = StubPaster()
        let viewModel = makeViewModel(["one", "two"], paster: paster)
        #expect(!viewModel.pasteClipboardShortcut(3), "the key goes on")
        #expect(!viewModel.pasteClipboardShortcut(0) && !viewModel.pasteClipboardShortcut(10))
        viewModel.clipboardQuery = "zzz"
        #expect(!viewModel.pasteFirstClipboardMatch())
        #expect(paster.pastes == 0 && viewModel.state == .expanded)
    }

    @Test func theKeysWorkOnlyWhileTheClipboardShows() {
        let paster = StubPaster()
        let viewModel = makeViewModel(["one", "two"], paster: paster)
        viewModel.setShelfMode(.files)
        #expect(!viewModel.pasteClipboardShortcut(1) && !viewModel.pasteFirstClipboardMatch())
        viewModel.setShelfMode(.clipboard)
        viewModel.select(.home)
        #expect(!viewModel.pasteClipboardShortcut(1))
    }

    @Test func withoutAccessibilityItCopiesAndSaysSo() async {
        let paster = StubPaster()
        paster.canPaste = false
        let viewModel = makeViewModel(["one", "two"], paster: paster)
        #expect(viewModel.pasteClipboardShortcut(2))
        await viewModel.pasteTask?.value
        #expect(pasted(viewModel) == "two" && paster.pastes == 0)
        #expect(viewModel.alert?.text == "Copied", "as clicking a card does")
        #expect(viewModel.state == .expanded, "it stays open")
    }

    @Test func keyCapsShowOnlyWhileCommandIsHeld() {
        #expect(ClipboardShortcut.keyCap(forIndex: 0, commandHeld: false) == nil)
        #expect(ClipboardShortcut.keyCap(forIndex: 0, commandHeld: true) == "\u{2318}1")
        #expect(ClipboardShortcut.keyCap(forIndex: 8, commandHeld: true) == "\u{2318}9")
        #expect(ClipboardShortcut.keyCap(forIndex: 9, commandHeld: true) == nil, "only the first nine")
        let digits = (0..<UInt16(40)).compactMap(ClipboardShortcut.digit(forKeyCode:))
        #expect(Set(digits) == Set(1...9), "the number row, once each")
        #expect(ClipboardShortcut.digit(forKeyCode: 29) == nil, "0 is not a paste key")
    }

    @Test func escClearsTheSearchBeforeItCloses() {
        let viewModel = TestSupport.makeViewModel()
        #expect(!viewModel.stepBack(), "nothing to step back from")
        viewModel.clipboardQuery = "abc"
        #expect(viewModel.stepBack() && viewModel.clipboardQuery.isEmpty)
        #expect(!viewModel.stepBack())
    }
}

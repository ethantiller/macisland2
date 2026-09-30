import AppKit
import Testing
@testable import MacIsland

@MainActor
struct ClipboardSearchTests {
    private func history(_ texts: String...) -> ClipboardHistory {
        let history = ClipboardHistory()
        for text in texts.reversed() { history.record(.text(text)) }
        return history
    }

    @Test func matchesTextIgnoringCaseAndAccents() {
        let history = history("Grocery list", "Café menu", "the Answer is 42")
        #expect(history.matches("cafe").count == 1)
        #expect(history.matches("ANSWER").count == 1)
        #expect(history.matches("zebra").isEmpty)
    }

    @Test func nothingTypedListsAllTextNewestFirst() {
        let history = history("newest", "older")
        history.record(.image(NSImage(size: NSSize(width: 4, height: 4))))
        let all = history.matches("  ")
        #expect(all.count == 2)
        if case .text(let text) = all[0].content { #expect(text == "newest") }
    }

    @Test func plainTextWritesOnlyTheStringType() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.setString("<b>rich</b>", forType: .html)
        ClipboardHistory().copyText("plain", to: pasteboard)
        #expect(pasteboard.types?.contains(.html) == false && pasteboard.types?.contains(.string) == true)
        #expect(pasteboard.string(forType: .string) == "plain")
    }

    @Test func aSnippetKeepsTheTextAndIsNamedByItsFirstLine() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.clipboard.record(.text("Hello there\nsecond line"))
        let entry = viewModel.clipboard.entries[0]
        viewModel.saveAsSnippet(entry)
        let snippet = viewModel.notes.snippets.first
        #expect(snippet?.title == "Hello there" && snippet?.text == "Hello there\nsecond line")
        #expect(viewModel.notes.selectedSnippetID == snippet?.id)
    }

    @Test func theKeywordsFindWhatFollows() {
        #expect(PaletteModel.clipboardQuery(from: "clip foo") == "foo")
        #expect(PaletteModel.clipboardQuery(from: "CB  foo bar") == "foo bar")
        #expect(PaletteModel.clipboardQuery(from: "clip") == "")
        #expect(PaletteModel.clipboardQuery(from: "clipboard") == nil)
        #expect(PaletteModel.clipboardQuery(from: "cbs x") == nil)
    }

    @Test func thePaletteListsMatchingCopiesAndReturnCopiesOne() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.clipboard.record(.text("alpha one"))
        viewModel.clipboard.record(.text("beta two"))
        let palette = PaletteModel(viewModel: viewModel)
        palette.query = "clip alpha"
        #expect(palette.results.first?.title == "alpha one")
        #expect(palette.results.first?.subtitle?.hasPrefix("Clipboard") == true)
        palette.query = "cb"
        #expect(palette.results.prefix(2).map(\.title) == ["beta two", "alpha one"])
    }
}

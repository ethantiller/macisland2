import AppKit
import Testing

@testable import MacIsland

@MainActor
struct ClipboardCopyTests {
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
}

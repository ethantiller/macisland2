import SwiftUI

/// Makes or edits a tool from one of the person's Shortcuts: which Shortcut, what to call it, and its icon. **Test** runs the
/// Shortcut once, on purpose.
///
/// The icon is an SF Symbol chosen here (`bolt.fill` to start). The glyph the Shortcuts app shows for a shortcut is in its own
/// database in a numbering of its own; it isn't read (see docs/plans/shortcut-icons.md).
struct ShortcutToolSheet: View {
    let original: ShortcutTool
    let onSave: (ShortcutTool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var shortcut: String
    @State private var title: String
    @State private var symbol: String
    @State private var shortcuts: [String] = []
    @State private var isLoading = true
    @State private var testResult: String?
    @State private var isTesting = false

    /// A few common glyphs, one click each.
    static let presets = [
        "bolt.fill", "star.fill", "paperplane.fill", "folder.fill", "doc.fill", "envelope.fill", "calendar",
        "clock.fill", "house.fill", "wand.and.stars", "moon.fill", "sun.max.fill", "music.note", "photo", "lock.fill",
        "gearshape.fill",
    ]

    init(tool: ShortcutTool, onSave: @escaping (ShortcutTool) -> Void) {
        original = tool
        self.onSave = onSave
        _shortcut = State(initialValue: tool.shortcut)
        _title = State(initialValue: tool.title)
        _symbol = State(initialValue: tool.systemImage)
    }

    private var draft: ShortcutTool {
        var tool = original
        tool.shortcut = shortcut
        tool.title = title
        tool.systemImage = symbol
        return tool
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    SettingsDropdown(
                        title: "Shortcut",
                        selection: Binding(get: { shortcut }, set: { choose($0) }),
                        options: (!shortcut.isEmpty && !shortcuts.contains(shortcut)
                            ? [DropdownOption(shortcut, shortcut)] : [])
                            + [DropdownOption("", isLoading ? "Loading\u{2026}" : "Choose\u{2026}")]
                            + DropdownOption.all(shortcuts) { $0 })
                    TextField("Label", text: $title, prompt: Text("Wind Down"))
                        .onChange(of: title) { _, new in
                            if new.count > ShortcutTool.maxTitleLength { title = String(new.prefix(ShortcutTool.maxTitleLength)) }
                        }
                } footer: {
                    if !isLoading, shortcuts.isEmpty {
                        Text("No Shortcuts found. Make one in the Shortcuts app first.")
                    } else {
                        Text("Runs the Shortcut with no input. Its own actions ask for their own permissions.")
                    }
                }
                Section {
                    HStack {
                        TextField("Symbol", text: $symbol, prompt: Text(ShortcutTool.defaultSymbol))
                        Image(systemName: CustomWidget.isValidSymbol(symbol) ? symbol : "questionmark.square.dashed")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                    }
                    if !symbol.isEmpty, !CustomWidget.isValidSymbol(symbol) {
                        Text("That isn\u{2019}t an SF Symbol name.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(Self.presets, id: \.self) { name in
                            Button {
                                symbol = name
                            } label: {
                                Image(systemName: name)
                                    .frame(width: 28, height: 24)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(name)
                            .accessibilityAddTraits(symbol == name ? .isSelected : [])
                        }
                    }
                } header: {
                    Text("Icon")
                } footer: {
                    Text("Pick a symbol. MacIsland can\u{2019}t read the icon the Shortcuts app shows for a shortcut.")
                }
                if let testResult {
                    Section("Test") { Text(testResult) }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button(isTesting ? "Testing\u{2026}" : "Test", action: test)
                    .disabled(shortcut.isEmpty || isTesting)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
            }
            .padding(16)
        }
        .frame(width: 460, height: 520)
        .task {
            shortcuts = await ShortcutsCLI.list()
            isLoading = false
        }
    }

    /// Choosing a Shortcut names the tool after it, unless it already has a name of its own.
    private func choose(_ name: String) {
        if title.isEmpty || title == shortcut { title = String(name.prefix(ShortcutTool.maxTitleLength)) }
        shortcut = name
    }

    private func test() {
        let name = shortcut
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            let finished = await ShortcutsCLI.run(shortcut: name)
            testResult = finished ? "It ran." : "It didn\u{2019}t finish. Open it in Shortcuts to see why."
        }
    }
}

import AppKit
import SwiftUI

/// Makes or edits a custom widget: a name and glyph, where its value comes from, and how stale it may get. **Test**
/// runs it once, on purpose, and shows what came back.
struct CustomWidgetSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case shortcut = "Shortcut"
        case web = "Web Value"
        case folder = "Folder"
        case command = "Command"

        var id: Self { self }
    }

    let original: CustomWidget
    let onSave: (CustomWidget) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var symbol: String
    @State private var kind: Kind
    @State private var shortcutName: String
    @State private var showsResult: Bool
    @State private var address: String
    @State private var path: String
    @State private var folder: String
    @State private var command: String
    @State private var maxAge: Int
    @State private var shortcuts: [String] = []
    @State private var testResult: TestResult?
    @State private var isTesting = false

    enum TestResult: Equatable {
        case value(String)
        case failure(String)
    }

    init(widget: CustomWidget, onSave: @escaping (CustomWidget) -> Void) {
        original = widget
        self.onSave = onSave
        _title = State(initialValue: widget.title)
        _symbol = State(initialValue: widget.systemImage)
        _maxAge = State(initialValue: widget.maxAgeMinutes)
        var kind = Kind.shortcut
        var shortcutName = ""
        var showsResult = true
        var address = ""
        var path = ""
        var folder = ""
        var command = ""
        switch widget.source {
        case .shortcut(let name, let result):
            shortcutName = name
            showsResult = result
        case .web(let url, let jsonPath):
            kind = .web
            address = url.absoluteString
            path = jsonPath ?? ""
        case .folder(let value):
            kind = .folder
            folder = value
        case .command(let value):
            kind = .command
            command = value
        }
        _kind = State(initialValue: kind)
        _shortcutName = State(initialValue: shortcutName)
        _showsResult = State(initialValue: showsResult)
        _address = State(initialValue: address)
        _path = State(initialValue: path)
        _folder = State(initialValue: folder)
        _command = State(initialValue: command)
    }

    /// What the fields describe.
    private var draft: CustomWidget {
        var widget = original
        widget.title = title
        widget.systemImage = symbol
        widget.maxAgeMinutes = maxAge
        switch kind {
        case .shortcut: widget.source = .shortcut(name: shortcutName, showsResult: showsResult)
        case .web:
            widget.source = .web(
                url: URL(string: address.trimmingCharacters(in: .whitespaces)) ?? URL(fileURLWithPath: "/"),
                path: path.isEmpty ? nil : path)
        case .folder: widget.source = .folder(path: folder)
        case .command: widget.source = .command(path: command)
        }
        return widget
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $title, prompt: Text("Stocks"))
                    HStack {
                        TextField("Symbol", text: $symbol, prompt: Text("chart.line.uptrend.xyaxis"))
                        Image(systemName: CustomWidget.isValidSymbol(symbol) ? symbol : "questionmark.square.dashed")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                    }
                    if !symbol.isEmpty, !CustomWidget.isValidSymbol(symbol) {
                        Text("That isn\u{2019}t an SF Symbol name.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    SettingsDropdown(
                        title: "Source", selection: $kind, options: DropdownOption.all(Kind.allCases, title: \.rawValue)
                    )
                    sourceFields
                } footer: {
                    Text(footer)
                }
                if kind != .shortcut || showsResult {
                    Section {
                        SettingsDropdown(
                            title: "Update", selection: $maxAge,
                            options: DropdownOption.all([5, 15, 30, 60]) { "Every \($0) Minutes" })
                    } footer: {
                        Text("Only while Home is open, and only when the value is that old.")
                    }
                }
                if let testResult {
                    Section("Test") {
                        switch testResult {
                        case .value(let text): Text(text)
                        case .failure(let reason):
                            Text(reason).foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button(isTesting ? "Testing\u{2026}" : "Test", action: test)
                    .disabled(!draft.isValid || isTesting)
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
        .task { shortcuts = await ShortcutsCLI.list() }
    }

    @ViewBuilder private var sourceFields: some View {
        switch kind {
        case .shortcut:
            SettingsDropdown(
                title: "Shortcut", selection: $shortcutName,
                options: (!shortcutName.isEmpty && !shortcuts.contains(shortcutName)
                    ? [DropdownOption(shortcutName, shortcutName)] : [])
                    + [DropdownOption("", "Choose\u{2026}")] + DropdownOption.all(shortcuts) { $0 })
            Toggle("Show Its Result", isOn: $showsResult)
        case .web:
            TextField("Address", text: $address, prompt: Text("https://api.example.com/price"))
            TextField("Value", text: $path, prompt: Text("data.0.price (or leave empty for the first line)"))
        case .folder:
            chooser(title: "Folder", value: folder, choose: { pick(folders: true) { folder = $0 } })
        case .command:
            chooser(title: "Program", value: command, choose: { pick(folders: false) { command = $0 } })
        }
    }

    private func chooser(title: String, value: String, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(value.isEmpty ? "None" : (value as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
            Spacer()
            Button("Choose\u{2026}", action: choose)
        }
        .accessibilityLabel(title)
    }

    private var footer: String {
        switch kind {
        case .shortcut:
            "Runs the Shortcut with no input. Its own actions ask for their own permissions. Without its result, the widget is a button."
        case .web:
            "One HTTPS request to the address you type, including its query, with no cookies or saved headers. Only what is shown is kept, in memory."
        case .folder:
            "Shows how many items are in the folder and the newest. Clicking it opens the folder."
        case .command:
            "Runs the file you choose, as you, with no arguments, a 5 second limit, and a minimal environment. It stays on this Mac: it is never exported, imported, or started by a link."
        }
    }

    private func pick(folders: Bool, assign: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folders
        panel.canChooseFiles = !folders
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { assign(url.path) }
    }

    private func test() {
        let widget = draft
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            if widget.isButton, case .shortcut(let name, _) = widget.source {
                let finished = await ShortcutsCLI.run(shortcut: name)
                testResult =
                    finished ? .value("It ran.") : .failure("It didn\u{2019}t finish. Open it in Shortcuts to see why.")
                return
            }
            do {
                let value = try await LiveWidgetFetcher().value(for: widget.source)
                testResult = .value([value.text, value.detail].compactMap { $0 }.joined(separator: "  \u{00B7}  "))
            } catch {
                testResult = .failure(error.localizedDescription)
            }
        }
    }
}

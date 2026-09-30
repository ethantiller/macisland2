import SwiftUI

/// The Settings sidebar: a search field (four fifths of the width) and the button that hides the sidebar (one fifth) above the
/// panes, which a search replaces with what it found.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @Binding var searchText: String
    let hideSidebar: () -> Void
    /// Something the search found was chosen.
    let onOpen: (SettingsSearchEntry) -> Void

    private var results: [SettingsSearchEntry] { SettingsSearch.results(for: searchText) }
    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            SidebarHeader(searchText: $searchText, hideSidebar: hideSidebar) {
                if let first = results.first { onOpen(first) }
            }
            .padding(.horizontal, 10)
            if isSearching {
                searchResults
            } else {
                List(
                    SettingsPane.allCases,
                    selection: Binding(get: { selection }, set: { if let pane = $0 { selection = pane } })
                ) {
                    Label($0.title, systemImage: $0.systemImage).tag($0)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var searchResults: some View {
        let found = results
        return List {
            ForEach(found) { entry in
                Button {
                    onOpen(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .lineLimit(1)
                        Label(entry.pane.title, systemImage: entry.pane.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(entry.title), \(entry.pane.title)")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if found.isEmpty {
                Text("No Settings Found")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The search field and the hide button, in the proportions of four to one however wide the sidebar is.
private struct SidebarHeader: View {
    @Binding var searchText: String
    let hideSidebar: () -> Void
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    private static let spacing: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - Self.spacing, 0)
            HStack(spacing: Self.spacing) {
                searchField
                    .frame(width: usable * 0.8)
                    .tourAnchor(.search)
                hideButton
                    .frame(width: usable * 0.2)
            }
        }
        .frame(height: 28)
    }

    private var searchField: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onExitCommand { searchText = "" }
                .accessibilityLabel("Search Settings")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(isFocused ? 0.11 : 0.07), in: shape)
        .overlay(
            shape.strokeBorder(isFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(shape)
        .onTapGesture { isFocused = true }
        // \u{2318}F from anywhere in the window.
        .background(
            Button("Search Settings") { isFocused = true }.keyboardShortcut("f").opacity(0).allowsHitTesting(false))
    }

    private var hideButton: some View {
        SidebarToggleButton(systemImage: "line.3.horizontal", help: "Hide Sidebar", action: hideSidebar)
    }
}

/// A small square button in the field style, for hiding the sidebar (three lines) and, where it was, showing it (the pane's icon).
struct SidebarToggleButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(isHovering ? 0.12 : 0.07), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

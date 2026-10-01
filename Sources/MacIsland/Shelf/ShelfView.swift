import AppKit
import QuickLook
import SwiftUI

/// Where a dragged file is about to land, decided by which half of the island it's over.
enum DropZone: Equatable {
    case shelf, airDrop

    static func destination(for target: DragTarget, locationX: CGFloat, width: CGFloat) -> Self {
        switch target {
        case .shelfAndAirDrop: locationX > width / 2 ? .airDrop : .shelf
        case .shelfOnly, .nothing: .shelf
        case .airDropOnly: .airDrop
        }
    }
}

enum ShelfMode: String, CaseIterable, Identifiable {
    case files = "Files"
    case clipboard = "Clipboard"

    var id: Self { self }
}

struct ShelfView: View {
    let viewModel: IslandViewModel
    let dropZone: DropZone?

    private var shelf: ShelfModel { viewModel.shelf }
    private var clipboard: ClipboardHistory { viewModel.clipboard }
    @State private var commandKeys = CommandKeyMonitor()

    /// The split drop target shows only while a file is actually being dragged, so a missed exit
    /// can never leave it covering the Shelf.
    static func showsDropTiles(zone: DropZone?, isFileDragActive: Bool) -> Bool {
        zone != nil && isFileDragActive
    }

    var body: some View {
        content
            // On the whole view, not on the files branch: the drop tiles leaving swaps branches, and the checks (which can show a
            // folder prompt) must not run in the middle of a drop.
            .onAppear {
                viewModel.sweepShelf()
                shelf.verify()
                syncCommandKeys(showing: viewModel.isClipboardShowing)
            }
            // The search is for this visit, and ⌘ is listened to only while the clipboard shows.
            .onDisappear {
                viewModel.clipboardQuery = ""
                syncCommandKeys(showing: false)
            }
            .onChange(of: viewModel.isClipboardShowing) { _, showing in syncCommandKeys(showing: showing) }
    }

    private func syncCommandKeys(showing: Bool) {
        if showing {
            commandKeys.start { viewModel.isCommandHeld = $0 }
        } else {
            commandKeys.stop { viewModel.isCommandHeld = $0 }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let dropZone, Self.showsDropTiles(zone: dropZone, isFileDragActive: viewModel.isFileDragActive) {
            HStack(spacing: 8) {
                switch viewModel.settings.dragTarget {
                case .shelfAndAirDrop:
                    DropTile(title: "Add to Shelf", systemImage: "tray.and.arrow.down", isTargeted: dropZone == .shelf)
                    DropTile(
                        title: "AirDrop", systemImage: nil, isTargeted: dropZone == .airDrop, tint: Theme.Tint.airDrop)
                case .shelfOnly:
                    DropTile(title: "Add to Shelf", systemImage: "tray.and.arrow.down", isTargeted: true)
                case .airDropOnly:
                    DropTile(title: "AirDrop", systemImage: nil, isTargeted: true, tint: Theme.Tint.airDrop)
                case .nothing:
                    EmptyView()
                }
            }
        } else {
            VStack(spacing: 6) {
                header
                // A result waiting for a choice takes the row, in either mode, until it is answered.
                if let result = viewModel.fileTools.pending.first {
                    ShelfResultStrip(
                        result: result, more: viewModel.fileTools.pending.count - 1,
                        onAdd: { viewModel.addResultToShelf(result) },
                        onReplace: { viewModel.replaceWithResult(result) },
                        onSave: { viewModel.saveResultToFolder(result) },
                        onDiscard: { viewModel.discardResult(result) })
                } else {
                    switch viewModel.shelfMode {
                    case .files: files
                    case .clipboard: clipboardList
                    }
                }
            }
            .quickLookPreview(quickLook, in: shelf.items)
        }
    }

    /// Quick Look for the Shelf's files, driven by the view model so Space and the menu share it.
    private var quickLook: Binding<URL?> {
        Binding(get: { viewModel.quickLookURL }, set: { viewModel.quickLookURL = $0 })
    }

    private var header: some View {
        HStack(spacing: 12) {
            if viewModel.settings.isOn(.clipboard) {
                SegmentedChoice(options: ShelfMode.allCases, selection: viewModel.shelfMode, title: \.rawValue) {
                    viewModel.setShelfMode($0)
                }
                .frame(width: Theme.Metrics.shelfChoiceWidth)
            }
            if viewModel.shelfMode == .clipboard, viewModel.settings.isOn(.clipboard), !clipboard.entries.isEmpty {
                ClipboardSearchField(viewModel: viewModel)
            } else {
                Spacer()
            }
            switch viewModel.shelfMode {
            case .files where !shelf.items.isEmpty:
                if FileTools.combinable(shelf.items).count > 1 {
                    ShelfTextButton(title: "Combine into PDF") { viewModel.fileTools.combinePDF(shelf.items) }
                }
                if shelf.items.count > 1 {
                    ShelfTextButton(title: "Zip All") { viewModel.fileTools.zip(shelf.items) }
                }
                ShelfTextButton(title: "Clear All", action: shelf.clear)
            case .clipboard where !clipboard.entries.isEmpty:
                ShelfTextButton(title: "Clear All", action: clipboard.clear)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var files: some View {
        if shelf.items.isEmpty {
            emptyState("Drop files here to keep them handy", systemImage: "tray.and.arrow.down")
        } else {
            ShelfRow {
                ForEach(shelf.items, id: \.self) { url in
                    ShelfItemView(url: url, viewModel: viewModel) { shelf.remove(url) }
                }
            }
        }
    }

    @ViewBuilder
    private var clipboardList: some View {
        let shown = viewModel.shownClipboardEntries
        if clipboard.entries.isEmpty {
            emptyState("Things you copy show up here", systemImage: "doc.on.clipboard")
        } else if shown.isEmpty {
            emptyState("Nothing matches", systemImage: "magnifyingglass")
        } else {
            ShelfRow {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    ClipboardCard(
                        entry: entry, query: viewModel.clipboardQuery,
                        keyCap: ClipboardShortcut.keyCap(forIndex: index, commandHeld: viewModel.isCommandHeld),
                        onAction: viewModel.perform,
                        onCopyText: { image in Task { await viewModel.fileTools.copyText(from: image) } },
                        onPlain: { viewModel.copyPlainText(entry) },
                        onSnippet: { viewModel.saveAsSnippet(entry) }
                    ) {
                        viewModel.copyFromClipboardHistory(entry)
                    } onRemove: {
                        clipboard.remove(entry)
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String, systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.innerRadius, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(Theme.Palette.tertiary)
            .overlay {
                Label(title, systemImage: systemImage)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
            }
    }
}

/// The Shelf's scrolling row of files or clipboard cards, as tall as the space under the header, so the items are centered in it
/// whether there is one or many. The height comes from a `GeometryReader`: `containerRelativeFrame(.vertical)` on the row inside the
/// horizontal `ScrollView` collapsed it to nothing in the app, so a dropped file never showed (`ShelfRowTests` checks for that).
struct ShelfRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content }
                    .frame(height: proxy.size.height)
            }
        }
    }
}

/// A copied text or image. Click to copy it again, drag it out to use it. Text that is a link, an
/// address, or a color adds one action along the bottom. An image has nothing over it: reading its text is in the right-click menu.
private struct ClipboardCard: View {
    let entry: ClipboardEntry
    /// What is typed in the search: the words that matched are drawn apart from the rest.
    let query: String
    /// The key that pastes this card, while ⌘ is held.
    let keyCap: String?
    let onAction: (SmartAction) -> Void
    let onCopyText: (NSImage) -> Void
    let onPlain: () -> Void
    let onSnippet: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
    }

    private var action: SmartAction? {
        if case .text(let text) = entry.content { SmartAction.detect(in: text) } else { nil }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button(action: onCopy) {
                content
                    .frame(width: Theme.Metrics.clipboardCardWidth)
                    .frame(maxHeight: .infinity)
                    .background(isHovering ? Theme.Palette.fillHover : Theme.Palette.fill, in: shape)
                    .clipShape(shape)
                    .contentShape(shape)
            }
            .buttonStyle(IslandButtonStyle())
            .onHover { isHovering = $0 }
            .onDrag { provider }
            .contextMenu {
                switch entry.content {
                case .text:
                    Button("Copy as Plain Text", action: onPlain)
                    Button("Save as Snippet", action: onSnippet)
                    Divider()
                case .image(let image):
                    Button("Copy Text from Image") { onCopyText(image) }
                    Divider()
                }
                Button("Remove", action: onRemove)
            }
            .help("Click to copy again. Drag out to use it.")
            .accessibilityLabel(accessibilityText)
            .accessibilityAction(named: "Remove", onRemove)

            if let action {
                ChipButton(title: action.title) { onAction(action) }
                    .padding(6)
            }
            if let keyCap {
                KeyCap(keyCap, spoken: "Command " + String(keyCap.dropFirst()))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Theme.Metrics.clipboardCardWidth)
    }

    /// The copy's text. While searching, the words that matched are bright and the rest is quiet.
    private func cardText(_ text: String) -> Text {
        guard !ClipboardSearch.words(query).isEmpty else { return Text(text).foregroundStyle(Theme.Palette.primary) }
        return ClipboardSearch.segments(of: query, in: text).reduce(Text("")) { result, part in
            result + Text(part.text).foregroundStyle(part.isMatch ? Theme.Palette.primary : Theme.Palette.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .text(let text):
            cardText(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(Theme.Typography.caption)
                .multilineTextAlignment(.leading)
                .lineLimit(action == nil ? 3 : 2)
                .padding(.leading, 8)
                .padding(.trailing, hasSwatch ? 28 : 8)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .topTrailing) { swatch }
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        }
    }

    private var hasSwatch: Bool {
        if case .color = action { true } else { false }
    }

    /// The color itself, beside its hex code. The swatch is arbitrary content, not a status tint.
    @ViewBuilder
    private var swatch: some View {
        if case .color(let hex, _) = action, let color = Color(hex: hex) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(
                        Theme.Palette.secondary, lineWidth: 1)
                )
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    private var provider: NSItemProvider {
        switch entry.content {
        case .text(let text): NSItemProvider(object: text as NSString)
        case .image(let image): NSItemProvider(object: image)
        }
    }

    private var accessibilityText: String {
        switch entry.content {
        case .text(let text): "Copy again: \(text.prefix(60))"
        case .image: "Copy image again"
        }
    }
}

private extension Color {
    /// `#RRGGBB` only, which is what `SmartAction` produces.
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// One half of the drop target. The targeted half is filled, like other "on" states. A tile with a `tint` (AirDrop)
/// is tinted all the time, with a soft fill even at rest, so it reads as a different place from the Shelf.
private struct DropTile: View {
    let title: String
    /// A symbol name, or `nil` for AirDrop, whose icon is drawn (`AirDropGlyph`).
    let systemImage: String?
    let isTargeted: Bool
    var tint: Color?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.innerRadius, style: .continuous)
    }

    /// The name, with its icon: a symbol, or the drawn AirDrop glyph.
    private var tileLabel: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            } else {
                AirDropGlyph()
            }
            Text(title)
        }
        .font(Theme.Typography.bodyEmphasized)
    }

    var body: some View {
        Group {
            if let tint {
                shape
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [5, 4]))
                    .foregroundStyle(tint.opacity(isTargeted ? 1 : 0.7))
                    .background(tint.opacity(isTargeted ? 0.3 : 0.14), in: shape)
                    .overlay { tileLabel.foregroundStyle(tint) }
            } else {
                shape
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [5, 4]))
                    .foregroundStyle(isTargeted ? Theme.Palette.primary : Theme.Palette.tertiary)
                    .background(isTargeted ? Theme.Palette.fill : Theme.Palette.none, in: shape)
                    .overlay { tileLabel.foregroundStyle(isTargeted ? Theme.Palette.primary : Theme.Palette.secondary) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

private struct ShelfTextButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(title, action: action)
            .font(Theme.Typography.bodyEmphasized)
            .foregroundStyle(isHovering ? Theme.Palette.primary : Theme.Palette.secondary)
            .buttonStyle(IslandButtonStyle())
            .onHover { isHovering = $0 }
    }
}

/// The ✕ on a hovered file: a disc in the island's own inks (an inverse glyph on a primary disc, as a selected `IconButton`), with a larger
/// area that takes the click.
private struct ShelfRemoveButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.Palette.inverse)
                .frame(width: Theme.Metrics.shelfRemove, height: Theme.Metrics.shelfRemove)
                .background(Theme.Palette.primary, in: Circle())
                .frame(width: Theme.Metrics.shelfRemoveHit, height: Theme.Metrics.shelfRemoveHit)
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
        .help("Remove from the Shelf")
        .accessibilityLabel("Remove \(name)")
    }
}

/// A result of Zip, Convert, and the rest, waiting for the person to say where it goes. It takes the Shelf's row until it is
/// answered, in either mode; with several waiting, the oldest shows first.
private struct ShelfResultStrip: View {
    let result: ShelfResult
    let more: Int
    let onAdd: () -> Void
    let onReplace: () -> Void
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: result.staged.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(more > 0 ? "\(result.verb) \u{00B7} \(more) more waiting" : result.verb)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            ChipButton(title: "Add to Shelf", isProminent: true, action: onAdd)
            ChipButton(title: "Replace", accessibilityLabel: "Replace the original on the Shelf", action: onReplace)
            ChipButton(title: "Save to Folder\u{2026}", action: onSave)
            IconButton(systemName: "xmark", label: "Discard \(result.name)", size: 11, action: onDiscard)
        }
        .frame(maxHeight: .infinity)
        .transition(.opacity)
    }
}

private struct ShelfItemView: View {
    let url: URL
    let viewModel: IslandViewModel
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    private var tools: FileTools { viewModel.fileTools }

    /// The file's own thumbnail once it arrives, its icon until then and when the system has none.
    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            preview
                .frame(width: Theme.Metrics.shelfThumbnail, height: Theme.Metrics.shelfThumbnail)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.nestedRadius, style: .continuous))
            Text(url.lastPathComponent)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 64)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                ShelfRemoveButton(name: url.lastPathComponent, action: onRemove)
                    .offset(x: Theme.Metrics.shelfRemoveHit / 4, y: -Theme.Metrics.shelfRemoveHit / 4)
            }
        }
        .contentShape(Rectangle())
        .onHover {
            isHovering = $0
            viewModel.setHoveredShelfItem($0 ? url : nil)
        }
        // A separate gesture, so waiting to see whether a click is a double click can't hold back the start of a drag.
        .simultaneousGesture(TapGesture(count: 2).onEnded { NSWorkspace.shared.open(url) })
        // A file provider copies the file where it is dropped, so dragging out never moves the original. The preview is the
        // file's own thumbnail instead of a snapshot of the whole item.
        .onDrag {
            NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        } preview: {
            preview.frame(width: Theme.Metrics.shelfThumbnail, height: Theme.Metrics.shelfThumbnail)
        }
        .task(id: ShelfThumbnails.key(for: url, size: Theme.Metrics.shelfThumbnail)) {
            thumbnail = await ShelfThumbnails.shared.image(for: url, size: Theme.Metrics.shelfThumbnail)
        }
        .contextMenu {
            Button("Quick Look") { viewModel.showQuickLook(url) }
            ShareLink("Share", item: url)
            Divider()
            let kind = FileKind.of(url)
            if kind == .image || kind == .pdf {
                Button(kind == .image ? "Copy Text from Image" : "Copy Text from PDF") {
                    Task { await tools.copyText(from: url) }
                }
            }
            Button("Zip") { tools.zip([url]) }
            if FileTools.isZip(url) {
                Button("Unzip") { tools.unzip(url) }
            }
            let targets = ConversionTarget.targets(for: url)
            if !targets.isEmpty {
                Menu("Convert To") {
                    ForEach(targets) { target in
                        Button(target.rawValue) { tools.convert(url, to: target) }
                    }
                }
            }
            if kind == .image {
                Menu("Resize") {
                    Button("Half Size") { tools.resize(url, maxPixel: nil) }
                    Button("1920 px") { tools.resize(url, maxPixel: 1920) }
                    Button("1280 px") { tools.resize(url, maxPixel: 1280) }
                }
                Button("Compress") { tools.compress(url) }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove", action: onRemove)
        }
        .help("\(url.lastPathComponent)\nDouble-click to open. Drag out to use it. Right-click for more.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { NSWorkspace.shared.open(url) }
        .accessibilityAction(named: "Remove", onRemove)
    }
}

import AppKit
import SwiftUI
import Testing

@testable import MacIsland

/// Renders every Home widget at every size it has, on black at 1:1, for design review. Opt-in, like `IslandSnapshots`:
/// `ISLAND_SNAPSHOT_DIR=/some/dir ./scripts/test.sh --filter WidgetSizeSnapshots`. One PNG per widget and size
/// (`31-widget-<id>-<w>x<h>.png`) and a sheet of all of them (`31-widget-sizes.png`).
@MainActor
struct WidgetSizeSnapshots {
    private let outputDirectory = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"].map(
        URL.init(fileURLWithPath:))

    /// A widget at a size, ready to draw.
    private struct Entry: Identifiable {
        let placement: WidgetPlacement
        let title: String
        let size: GridSize

        var id: String { "\(placement.widget.rawValue)-\(size)" }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderEverySize() async throws {
        let viewModel = TestSupport.makeViewModel()
        viewModel.nowPlaying.apply(PreviewSamples.track())
        viewModel.agenda.showSample(
            PreviewSamples.nextEvent(), upcoming: PreviewSamples.upcoming(), reminders: PreviewSamples.reminders())
        for notification in PreviewSamples.notifications().inbox.items.reversed() {
            viewModel.notifications.inbox.add(notification)
        }
        let note = viewModel.notes.addNote()
        viewModel.notes.setBody(
            "Talking points\nOpen with the demo, then the numbers.\nSlow down on pricing.\nAsk about the rollout.\n"
                + "Leave time for questions.\nFollow up on Friday.\nSend the deck.",
            ofNote: note.id)
        let weather = viewModel.weather
        weather.typingPause = .zero
        weather.usesFahrenheit = false
        weather.fetch = PreviewSamples.weatherResponse
        weather.configure(city: "Paris")
        for _ in 0..<100 where weather.conditions == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(weather.conditions?.days.count == 5 && weather.conditions?.hours.count == 5)

        let value = CustomWidget(
            title: "Price", systemImage: "chart.line.uptrend.xyaxis", source: .folder(path: "/tmp"))
        let button = CustomWidget(
            title: "Run", systemImage: "play.fill", source: .shortcut(name: "X", showsResult: false))
        viewModel.settings.saveCustomWidget(value)
        viewModel.settings.saveCustomWidget(button)

        var entries: [[Entry]] = []
        let widgets: [WidgetID] =
            BuiltInWidget.allCases.map { .builtIn($0) } + [.custom(value.id), .custom(button.id)]
        for widget in widgets {
            guard let descriptor = viewModel.settings.widgetDescriptor(for: widget) else { continue }
            entries.append(
                descriptor.sizes.map {
                    Entry(placement: WidgetPlacement(widget: widget, size: $0), title: descriptor.title, size: $0)
                })
        }

        for entry in entries.joined() {
            write(
                drawn(entry, viewModel).padding(16).background(Color.black),
                "31-widget-\(entry.placement.widget.rawValue.replacingOccurrences(of: ":", with: "-"))-\(entry.size)")
        }
        write(sheet(entries, viewModel), "31-widget-sizes", scale: 1)
    }

    private func drawn(_ entry: Entry, _ viewModel: IslandViewModel) -> some View {
        HomeWidgetView(placement: entry.placement, size: entry.size, viewModel: viewModel)
            .frame(
                width: HomeGridSpec.width(columns: entry.size.columns),
                height: HomeGridSpec.height(rows: entry.size.rows))
    }

    /// Every widget and size, wrapped into lines no wider than the sheet.
    private func sheet(_ widgets: [[Entry]], _ viewModel: IslandViewModel) -> some View {
        let maxWidth: CGFloat = 1_000
        return VStack(alignment: .leading, spacing: 28) {
            ForEach(Array(widgets.enumerated()), id: \.offset) { _, sizes in
                VStack(alignment: .leading, spacing: 10) {
                    Text(sizes.first?.title ?? "")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.primary)
                    ForEach(Array(lines(sizes, maxWidth: maxWidth).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(line) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    drawn(entry, viewModel)
                                    Text(entry.size.displayName)
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Palette.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: maxWidth + 48, alignment: .leading)
        .background(Color.black)
    }

    private func lines(_ entries: [Entry], maxWidth: CGFloat) -> [[Entry]] {
        var lines: [[Entry]] = [[]]
        var used: CGFloat = 0
        for entry in entries {
            let width = HomeGridSpec.width(columns: entry.size.columns)
            if used + width > maxWidth, !lines[lines.count - 1].isEmpty {
                lines.append([])
                used = 0
            }
            lines[lines.count - 1].append(entry)
            used += width + 16
        }
        return lines
    }

    private func write(_ content: some View, _ name: String, scale: CGFloat = 2) {
        guard let outputDirectory else { return }
        let renderer = ImageRenderer(content: content.environment(\.isSnapshot, true))
        renderer.scale = scale
        guard let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}

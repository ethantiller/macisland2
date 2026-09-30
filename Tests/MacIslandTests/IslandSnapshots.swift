import AppKit
import SwiftUI
import Testing
@testable import MacIsland

/// Renders each island state to PNGs for design review. Opt-in:
/// `ISLAND_SNAPSHOT_DIR=/some/dir ./scripts/test.sh --filter IslandSnapshots`
@MainActor
struct IslandSnapshots {
    private let outputDirectory = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"].map(URL.init(fileURLWithPath:))

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderStates() async throws {
        let viewModel = makeViewModel()

        render(viewModel, "01-compact-idle")

        var paused = sampleTrack()
        paused.isPlaying = false
        viewModel.nowPlaying.apply(paused)
        render(viewModel, "02-compact-media-paused")

        viewModel.nowPlaying.apply(sampleTrack())
        render(viewModel, "03-compact-media-playing")

        viewModel.setHovering(true)
        render(viewModel, "01b-compact-swell")
        viewModel.setHovering(false)

        viewModel.state = .peek
        render(viewModel, "03b-peek-media")

        // Home, with weather from a stubbed Open-Meteo.
        let weather = viewModel.weather
        weather.typingPause = .zero
        weather.usesFahrenheit = false
        weather.fetch = { url in
            if url.host == "geocoding-api.open-meteo.com" {
                return Data(#"{"results":[{"name":"Paris","latitude":48.85,"longitude":2.35}]}"#.utf8)
            }
            return Data(#"{"current":{"temperature_2m":18.4,"weather_code":2,"is_day":1}}"#.utf8)
        }
        weather.configure(city: "Paris")
        try await Task.sleep(for: .milliseconds(100))
        let playing = viewModel.nowPlaying.state
        viewModel.nowPlaying.apply(NowPlayingState())
        viewModel.state = .peek
        render(viewModel, "03e-peek-idle-weather")
        viewModel.nowPlaying.apply(playing)
        viewModel.state = .expanded
        viewModel.selectedTab = .home
        render(viewModel, "04a-expanded-home")
        viewModel.setCalendarExpanded(true)
        render(viewModel, "04a-expanded-home-calendar")
        viewModel.setCalendarExpanded(false)
        viewModel.timer.start(minutes: 25)
        render(viewModel, "04a-expanded-home-timer-strip")
        viewModel.timer.reset()
        viewModel.settings.move(.notes, to: .right)
        render(viewModel, "04e-right-tab")
        viewModel.timer.start(minutes: 25)
        render(viewModel, "04e-right-tab-timer")
        viewModel.timer.reset()
        viewModel.settings.setEnabled(.notes, false)

        viewModel.state = .expanded
        viewModel.selectedTab = .media
        render(viewModel, "04-expanded-media")

        let lyrics = viewModel.nowPlaying.lyrics
        lyrics.fetch = { _ in Data(#"{"syncedLyrics": "[00:00.00] Waiting in a car, waiting for a ride in the dark"}"#.utf8) }
        lyrics.setEnabled(true, for: NowPlayingState())
        viewModel.nowPlaying.apply(sampleTrack())
        viewModel.nowPlaying.toggleShuffle()
        viewModel.nowPlaying.cycleRepeat()
        try await Task.sleep(for: .milliseconds(100))
        // The pointer-left step earlier schedules a close 300 ms later, which may have landed by now.
        viewModel.state = .expanded
        render(viewModel, "04b-expanded-media-lyrics")
        viewModel.state = .peek
        render(viewModel, "03d-peek-media-lyrics")
        viewModel.state = .expanded
        lyrics.setEnabled(false, for: viewModel.nowPlaying.state)

        viewModel.selectedTab = .shelf
        render(viewModel, "05-expanded-shelf-empty")

        viewModel.selectedTab = .shelf
        viewModel.setShelfMode(.clipboard)
        viewModel.clipboard.record(.text("https://example.com/a-long-link-to-share"))
        viewModel.clipboard.record(.text("Meeting notes: ship the island"))
        viewModel.clipboard.record(.text("#FF5733"))
        viewModel.clipboard.record(.text("hello@example.com"))
        render(viewModel, "05b-expanded-clipboard")
        viewModel.setShelfMode(.files)

        viewModel.timer.start(minutes: 25)
        viewModel.selectedTab = .clock
        render(viewModel, "06-expanded-timer")

        viewModel.clockMode = .pomodoro
        viewModel.pomodoro.toggle()
        viewModel.pomodoro.advance(completed: true)
        viewModel.pomodoro.advance(completed: true)
        viewModel.pomodoro.advance(completed: true)
        render(viewModel, "06b-expanded-pomodoro")
        viewModel.pomodoro.reset()

        viewModel.clockMode = .stopwatch
        viewModel.stopwatch.toggle(at: Date().addingTimeInterval(-83.4))
        viewModel.stopwatch.lap(at: Date().addingTimeInterval(-40))
        render(viewModel, "07-expanded-stopwatch")

        viewModel.selectedTab = .tools
        viewModel.keepAwake.toggle()
        viewModel.keepAwake.start(.until(Date().addingTimeInterval(7200)))
        render(viewModel, "08-expanded-tools")
        viewModel.setToolsExpanded(true)
        render(viewModel, "08a-expanded-tools-more")
        viewModel.settings.pinLimit = .eight
        viewModel.setToolsExpanded(false)
        render(viewModel, "08c-expanded-tools-eight")
        viewModel.settings.pinLimit = .six
        viewModel.setToolsExpanded(true)
        viewModel.setToolsExpanded(false)

        viewModel.keepAwake.toggle()

        viewModel.state = .peek
        viewModel.clockMode = .timer
        render(viewModel, "03c-peek-timer")

        let note = viewModel.notes.addNote()
        viewModel.notes.setBody("Talking points\nOpen with the demo, then the numbers.", ofNote: note.id)
        let snippet = viewModel.notes.addSnippet()
        viewModel.notes.setTitle("Sign-off", ofSnippet: snippet.id)
        viewModel.notes.setText("Best regards,\nEthan", ofSnippet: snippet.id)
        viewModel.settings.toggleTab(.tools)
        viewModel.settings.toggleTab(.notes)
        viewModel.state = .expanded
        viewModel.selectedTab = .notes
        render(viewModel, "08d-expanded-notes")
        viewModel.settings.toggleTab(.notes)
        viewModel.settings.toggleTab(.tools)

        viewModel.timer.start(minutes: 25)
        viewModel.state = .peek
        render(viewModel, "03f-peek-timer-compact")
        viewModel.timer.reset()
        viewModel.pomodoro.toggle()
        render(viewModel, "03g-peek-pomodoro")
        viewModel.pomodoro.reset()
        viewModel.stopwatch.toggle(at: Date().addingTimeInterval(-83.4))
        viewModel.stopwatch.lap(at: Date().addingTimeInterval(-40))
        render(viewModel, "03h-peek-stopwatch")
        viewModel.stopwatch.reset()
        viewModel.state = .expanded
        viewModel.selectedTab = .reminders
        render(viewModel, "04c-expanded-reminders")
        viewModel.timer.start(minutes: 25)

        viewModel.state = .compact
        render(viewModel, "09-compact-timer")
        viewModel.stopwatch.reset()

        viewModel.nowPlaying.apply(sampleTrack())
        render(viewModel, "09b-compact-pair-timer-media")
        viewModel.nowPlaying.apply(NowPlayingState())

        viewModel.flash(IslandAlert(systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "87%"))
        render(viewModel, "10-compact-alert")

        viewModel.showBanner(IslandBanner(
            systemImage: "airpodspro", tint: Theme.Tint.neutral, title: "AirPods Pro", detail: "L 80%   R 75%   Case 60%"
        ))
        render(viewModel, "11-banner-airpods")

        viewModel.showBanner(IslandBanner(
            systemImage: "battery.25percent", tint: Theme.Tint.attention, title: "Low Battery",
            detail: "20% remaining", action: .init(title: "Low Power Mode") {}
        ))
        render(viewModel, "12-banner-low-battery")

        // The banner outranks an alert, so let it go first.
        viewModel.performBannerAction()
        viewModel.flash(IslandAlert(
            systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "82%", isCharging: true
        ))
        render(viewModel, "13-compact-charging")

        viewModel.timer.reset()
        viewModel.stopwatch.reset()
    }

    private func makeViewModel() -> IslandViewModel { TestSupport.makeViewModel() }

    /// The two drop tiles the Shelf shows while a file is dragged, as they look with the pointer over each half.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderDropTiles() {
        let viewModel = makeViewModel()
        viewModel.setFileDragActive(true)
        for (name, zone) in [("14-drop-tiles-shelf", DropZone.shelf), ("14b-drop-tiles-airdrop", DropZone.airDrop)] {
            let content = ShelfView(viewModel: viewModel, dropZone: zone)
                .frame(width: 472, height: Theme.Metrics.shelfHeight)
                .padding(18)
                .background(Color.black)
            guard let outputDirectory, let image = ImageRenderer(content: content).nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        }
        viewModel.setFileDragActive(false)
    }

    private func sampleTrack() -> NowPlayingState {
        var state = NowPlayingState()
        state.title = "Midnight City"
        state.artist = "M83"
        state.isPlaying = true
        state.playbackRate = 1
        state.duration = 243
        state.elapsedTime = 81
        state.timestamp = Date()
        state.artworkBase64 = sampleArtwork().base64EncodedString()
        return state
    }

    private func sampleArtwork() -> Data {
        let image = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
            NSGradient(colors: [
                NSColor(srgbRed: 0.10, green: 0.05, blue: 0.35, alpha: 1),
                NSColor(srgbRed: 0.85, green: 0.20, blue: 0.55, alpha: 1),
            ])?.draw(in: rect, angle: 60)
            return true
        }
        let tiff = image.tiffRepresentation ?? Data()
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) ?? Data()
    }

    private func render(_ viewModel: IslandViewModel, _ name: String) {
        guard let outputDirectory else { return }
        let content = IslandView(viewModel: viewModel, acceptsDrops: false)
            .frame(width: ScreenGeometry.panelSize.width, height: max(viewModel.size.height, 1) + 16, alignment: .top)
            .background(Color(white: 0.28))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}

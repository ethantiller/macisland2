import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    let viewModel: IslandViewModel
    /// Off only for snapshots: `ImageRenderer` draws a drop target as a yellow placeholder.
    var acceptsDrops = true

    @State private var dropZone: DropZone?
    /// Shared with the peek and the Media tab, so the art and the bars travel between them.
    @Namespace private var mediaNamespace

    private var notchSize: CGSize { viewModel.geometry.notchSize }
    private var edgeInset: CGFloat { ScreenGeometry.topFlare + Theme.Metrics.margin }

    var body: some View {
        IslandContainer(
            presentation: viewModel.presentation,
            size: viewModel.size,
            surface: viewModel.geometry.hasNotch ? .hardware : .glass,
            isSwelling: viewModel.isSwelling
        ) {
            ZStack(alignment: .top) {
                switch viewModel.presentation {
                case .expanded:
                    expandedContent
                        .transition(Theme.Motion.content)
                case .peek:
                    PeekContent(viewModel: viewModel)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.open() }
                        .transition(Theme.Motion.content)
                case .banner:
                    if let banner = viewModel.banner {
                        BannerContent(banner: banner, notchHeight: notchSize.height, edgeInset: edgeInset) {
                            viewModel.performBannerAction()
                        }
                        .transition(Theme.Motion.content)
                    }
                case .compact:
                    compactLayer
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.open() }
                        .transition(.opacity)
                }
            }
        }
        .environment(\.mediaNamespace, mediaNamespace)
        .modifier(DropTarget(enabled: acceptsDrops, delegate: IslandDropDelegate(viewModel: viewModel, zone: $dropZone)))
        // When the drag ends, however it ends, the drop target goes with it.
        .onChange(of: viewModel.isFileDragActive) { _, active in
            if !active { dropZone = nil }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The compact halves, plus the Shelf / AirDrop labels while a file is dragged toward the island.
    private var compactLayer: some View {
        ZStack(alignment: .top) {
            compactContent
            if viewModel.showsDragTarget {
                HStack(spacing: 0) {
                    dragHint("Shelf", systemImage: "tray.and.arrow.down")
                    dragHint("AirDrop", systemImage: "airdrop")
                }
                .padding(.top, notchSize.height)
                .padding(.horizontal, edgeInset)
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(viewModel.leftTabs()) { tab in
                        TabButton(tab: tab, isSelected: viewModel.selectedTab == tab, viewModel: viewModel) {
                            viewModel.select(tab)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Sections")

                Spacer(minLength: notchSize.width)

                trailingStrip
                    .frame(maxWidth: viewModel.trailingStripWidth, alignment: .trailing)
            }
            .padding(.horizontal, ScreenGeometry.topFlare + 10)
            .frame(height: notchSize.height)

            selectedTabContent
                .frame(height: viewModel.currentContentHeight, alignment: .top)
                .padding(.horizontal, edgeInset)
                .padding(.top, Theme.Metrics.contentTopGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Live status, then the weather and a new note if there is room, then the right-hand tab, then Settings.
    private var trailingStrip: some View {
        HStack(spacing: 4) {
            StatusIndicators(viewModel: viewModel)
            if viewModel.showsStripWeather, let conditions = viewModel.weather.conditions {
                WeatherGlance(conditions: conditions)
                    .padding(.horizontal, 4)
            }
            if viewModel.showsStripPencil {
                IconButton(systemName: "square.and.pencil", label: "New Note", size: 12) { viewModel.openQuickNote() }
            }
            ForEach(viewModel.rightTabs()) { tab in
                TabButton(tab: tab, isSelected: viewModel.selectedTab == tab, viewModel: viewModel) { viewModel.select(tab) }
            }
            SettingsButton()
        }
    }

    private var selectedTabContent: some View {
        ModuleContent(module: viewModel.selectedTab, viewModel: viewModel, dropZone: dropZone)
    }

    // MARK: Compact

    /// Names one half of the drop target while a file is being dragged toward the island.
    private func dragHint(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(Theme.Typography.title)
            .foregroundStyle(Theme.Palette.secondary)
            .frame(maxWidth: .infinity)
    }

    /// Leading and trailing halves hug the notch and describe the same activity.
    private var compactContent: some View {
        HStack(spacing: 0) {
            if let pair = viewModel.compactPair {
                pairSide(pair.leading)
                Spacer(minLength: 0)
                pairSide(pair.trailing)
            } else {
                compactLeading
                Spacer(minLength: 0)
                compactTrailing
            }
        }
        .padding(.horizontal, ScreenGeometry.topFlare + 10)
        .frame(height: notchSize.height)
    }

    /// One side of a minimal pair: only the activity's glyph, ring, or artwork.
    @ViewBuilder
    private func pairSide(_ activity: CompactActivity) -> some View {
        switch activity {
        case .microphone:
            AppIcon(bundleID: viewModel.privacy.microphoneAppBundleID, fallback: "mic.fill")
        case .timer:
            CompactTimerRing(timer: viewModel.timer)
        case .pomodoro:
            CompactPomodoroRing(pomodoro: viewModel.pomodoro)
        case .stopwatch:
            Glyph(systemName: "stopwatch", tint: Theme.Tint.clock)
        case .working:
            WorkingGlyph()
        case .transfer:
            TransferIcon(transfers: viewModel.transfers)
        case .media:
            ArtworkView(image: viewModel.nowPlaying.artwork, size: notchSize.height - 12, cornerRadius: 5)
                .mediaMatch("artwork")
        case .alert, .banner, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var compactLeading: some View {
        switch viewModel.compactActivity {
        case .alert(let alert):
            if alert.isCharging {
                ChargingBadge(size: notchSize.height - 10)
            } else {
                Glyph(systemName: alert.systemImage, tint: alert.tint)
            }
        case .microphone:
            AppIcon(bundleID: viewModel.privacy.microphoneAppBundleID, fallback: "mic.fill")
        case .timer:
            CompactTimerRing(timer: viewModel.timer)
        case .pomodoro:
            CompactPomodoroRing(pomodoro: viewModel.pomodoro)
        case .stopwatch:
            Glyph(systemName: "stopwatch", tint: Theme.Tint.clock)
        case .working:
            WorkingGlyph()
        case .transfer:
            TransferIcon(transfers: viewModel.transfers)
        case .media:
            ArtworkView(image: viewModel.nowPlaying.artwork, size: notchSize.height - 12, cornerRadius: 5)
                .mediaMatch("artwork")
        case .banner, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var compactTrailing: some View {
        switch viewModel.compactActivity {
        case .alert(let alert):
            Text(alert.text)
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(alert.tintsText ? AnyShapeStyle(alert.tint) : AnyShapeStyle(Theme.Palette.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case .microphone:
            if let since = viewModel.privacy.microphoneSince {
                ElapsedText(since: since)
            }
        case .timer:
            CompactTimerText(timer: viewModel.timer)
        case .pomodoro:
            CompactPomodoroText(pomodoro: viewModel.pomodoro)
        case .stopwatch:
            CompactStopwatchText(stopwatch: viewModel.stopwatch)
        case .working(let title):
            Text(title)
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Tint.working)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case .transfer:
            Text("\(Int((viewModel.transfers.overallFraction * 100).rounded()))%")
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Palette.primary)
                .contentTransition(.numericText())
        case .media:
            CompactPlaybackControl(nowPlaying: viewModel.nowPlaying)
        case .banner, .none:
            EmptyView()
        }
    }
}

// MARK: - Drop

/// The island as a drop target for files, unless it is turned off.
private struct DropTarget: ViewModifier {
    let enabled: Bool
    let delegate: IslandDropDelegate

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.fileURL], delegate: delegate)
        } else {
            content
        }
    }
}

/// Dragging a file onto the island opens the Shelf tab split in two: the left half keeps the
/// file, the right half hands it to AirDrop.
private struct IslandDropDelegate: DropDelegate {
    let viewModel: IslandViewModel
    @Binding var zone: DropZone?

    private func zone(for info: DropInfo) -> DropZone {
        info.location.x > viewModel.size.width / 2 ? .airDrop : .shelf
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        zone = zone(for: info)
        viewModel.setDropTargeted(true)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        zone = zone(for: info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        zone = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = zone(for: info)
        zone = nil
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let shelf = viewModel.shelf
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let url = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                }
                if let url { urls.append(url) }
            }
            switch target {
            case .shelf: shelf.add(urls)
            case .airDrop: shelf.airDrop(urls)
            }
        }
        return true
    }
}

// MARK: - Pieces

/// Live state beside the notch that the current tab would otherwise hide. At most two.
private struct StatusIndicators: View {
    let viewModel: IslandViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.timer.isActive && viewModel.selectedTab != .clock {
                CompactTimerText(timer: viewModel.timer)
            } else if viewModel.pomodoro.isActive && viewModel.selectedTab != .clock {
                CompactPomodoroText(pomodoro: viewModel.pomodoro)
            } else if viewModel.stopwatch.isRunning && viewModel.selectedTab != .clock {
                CompactStopwatchText(stopwatch: viewModel.stopwatch)
            }
            if viewModel.keyboardCleaner.isLocked {
                statusGlyph("keyboard", "Keyboard is locked")
            } else if viewModel.network.isOnHotspot {
                statusGlyph("personalhotspot", "Connected to Personal Hotspot")
            } else if viewModel.ringLight.isOn {
                statusGlyph("lightbulb.fill", "Ring Light is on")
            } else if viewModel.keepAwake.isOn {
                statusGlyph("cup.and.saucer.fill", "Keep Awake is on")
            }
        }
    }

    private func statusGlyph(_ systemName: String, _ label: String) -> some View {
        Image(systemName: systemName)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.secondary)
            .help(label)
            .accessibilityLabel(label)
    }
}

private struct BannerContent: View {
    let banner: IslandBanner
    let notchHeight: CGFloat
    let edgeInset: CGFloat
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(banner.tint)
                .symbolEffect(.bounce, value: banner.id)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primary)
                if let detail = banner.detail {
                    Text(detail)
                        .font(Theme.Typography.body.monospacedDigit())
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if let action = banner.action {
                ChipButton(title: action.title, action: onAction)
            }
        }
        .padding(.horizontal, edgeInset)
        .padding(.top, notchHeight)
        .frame(maxHeight: .infinity)
    }
}

private struct AppIcon: View {
    let bundleID: String?
    let fallback: String

    var body: some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityLabel(FileManager.default.displayName(atPath: url.path))
        } else {
            Image(systemName: fallback)
                .font(Theme.Typography.glyph)
                .foregroundStyle(Theme.Palette.primary)
        }
    }
}

private struct ElapsedText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(formatTime(context.date.timeIntervalSince(since)))
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Palette.primary)
        }
    }
}

private struct TransferIcon: View {
    let transfers: TransferMonitor

    var body: some View {
        ZStack {
            ProgressRing(progress: transfers.overallFraction, tint: Theme.Tint.neutral, lineWidth: 2)
            if let url = transfers.transfers.first?.displayURL {
                Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: url.pathExtension) ?? .data))
                    .resizable()
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityLabel("Download progress")
    }
}

/// Glyph tab. Selection is shown by shape (a filled capsule) and brightness, not color alone.
private struct TabButton: View {
    let tab: IslandModule
    let isSelected: Bool
    let viewModel: IslandViewModel
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.systemImage)
                .font(Theme.Typography.glyph)
                .foregroundStyle(isSelected || isHovering ? Theme.Palette.primary : Theme.Palette.tertiary)
                .frame(width: 26, height: 24)
                .background(isSelected ? Theme.Palette.fill : Theme.Palette.none, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(IslandButtonStyle())
        .onHover { isHovering = $0 }
        .help(tab.title)
        .contextMenu {
            Button(viewModel.settings.isInMenuBar(tab) ? "Hide from Menu Bar" : "Show in Menu Bar") {
                viewModel.settings.setInMenuBar(tab, !viewModel.settings.isInMenuBar(tab))
            }
            Button("Open in Window") { viewModel.openWindow(tab) }
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Opens the Settings window. The island is a panel over other apps, so the app is activated first.
private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        IconButton(systemName: "gearshape.fill", label: "Settings", size: 12) {
            NSApp.activate()
            openSettings()
        }
    }
}

/// Beside the notch while something is being worked on: a pulsing glyph in the "in progress" blue.
private struct WorkingGlyph: View {
    var body: some View {
        Glyph(systemName: "gearshape.2.fill", tint: Theme.Tint.working)
            .symbolEffect(.pulse)
    }
}

import SwiftUI

/// The namespace the compact island, the peek, and the Media tab share, so the album art and the sound bars
/// travel from one to the next instead of appearing.
private struct MediaNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var mediaNamespace: Namespace.ID? {
        get { self[MediaNamespaceKey.self] }
        set { self[MediaNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Ties this view to the same view in the other presentation, if the island has set a namespace.
    func mediaMatch(_ id: String, enabled: Bool = true) -> some View {
        modifier(MediaMatch(id: id, enabled: enabled))
    }
}

private struct MediaMatch: ViewModifier {
    let id: String
    let enabled: Bool

    @Environment(\.mediaNamespace) private var namespace

    func body(content: Content) -> some View {
        if enabled, let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// The music player, after the Dynamic Island's: the art, the song and who plays it with the sound bars at the
/// far side, the scrubber, then big transport buttons in the middle. In the Media tab the art is larger and the
/// player sits a little lower, and shuffle, repeat, and Favorite flank the transport; the peek is narrower and
/// leaves them out.
struct NowPlayingView: View {
    let nowPlaying: NowPlayingModel
    let outputs: AudioOutputs
    let bluetooth: BluetoothDevices
    /// The peek is narrower and only needs transport, so shuffle, repeat, and Favorite stay in the Media tab.
    var isPeek = false
    /// Drawn inside a Home widget: the peek's player, without the art and bars flying to the other presentations,
    /// the lyric line, or the output picker.
    var inWidget = false
    /// The island, when this is the Media tab: the Audio Output button's panel is kept there (so its height and Esc can see it), and
    /// it opens the Mixer instead of the output chips while the Mixer is on.
    var viewModel: IslandViewModel?
    var peekOutputList: Binding<Bool>?

    @State private var localShowsOutputs = false
    @State private var localShowsOutputList = false

    private var showsOutputs: Bool {
        get { viewModel?.showsMediaOutputs ?? localShowsOutputs }
        nonmutating set {
            if let viewModel { viewModel.showsMediaOutputs = newValue } else { localShowsOutputs = newValue }
        }
    }

    /// The Mixer's panel is what the button opened.
    private var showsMixer: Bool { showsOutputs && !isCompact && viewModel?.isMixerOn == true }

    private var showsOutputList: Bool {
        get { peekOutputList?.wrappedValue ?? localShowsOutputList }
        nonmutating set {
            if isPeek, let peekOutputList {
                peekOutputList.wrappedValue = newValue
            } else {
                localShowsOutputList = newValue
            }
        }
    }

    private var outputListBinding: Binding<Bool> {
        Binding(get: { showsOutputList }, set: { showsOutputList = $0 })
    }

    private var state: NowPlayingState { nowPlaying.state }
    private var isCompact: Bool { isPeek || inWidget }
    private var artworkSize: CGFloat { isCompact ? Theme.Metrics.playerPeekArtwork : Theme.Metrics.playerArtwork }

    var body: some View {
        VStack(spacing: Theme.Metrics.playerSpacing) {
            header

            if showsMixer, mixerListsPlayer {
                // The Mixer's first row is this app's volume, so the slot above the transport goes back to the scrubber.
                ScrubberRow(nowPlaying: nowPlaying)
                    .transition(.opacity)
            } else if showsMixer {
                volumeRow
            } else if isPeek {
                VStack(spacing: Theme.Metrics.playerSpacing) {
                    HStack(spacing: 12) {
                        if nowPlaying.appVolume != nil {
                            VolumeControl(nowPlaying: nowPlaying, style: .inline)
                        }
                        CurrentOutputChip(outputs: outputs, isOpen: outputListBinding)
                            .layoutPriority(1)
                    }
                    .frame(height: Theme.Metrics.outputRowHeight)

                    if showsOutputList {
                        OutputList(outputs: outputs, bluetooth: bluetooth, isOpen: outputListBinding)
                            .transition(.opacity)
                    }
                }
                    .transition(.opacity)
            } else if showsOutputs {
                volumeRow
            } else {
                ScrubberRow(nowPlaying: nowPlaying)
                    .transition(.opacity)
            }

            if !showsOutputList {
                transport

                if !showsMixer, !inWidget, !nowPlaying.lyrics.lines.isEmpty {
                    LyricLineView(nowPlaying: nowPlaying)
                        .transition(.opacity)
                }
            }

            if showsMixer, let viewModel {
                MixerPanel(viewModel: viewModel, canHide: true)
                    .transition(.opacity)
            }
        }
        .padding(.top, isCompact ? 0 : Theme.Metrics.playerTopInset)
        .animation(Theme.Motion.resize, value: outputs.defaultDeviceID)
        .animation(Theme.Motion.resize, value: showsOutputs)
        // Asked for while the view is visible, so a first Automation prompt comes from something the person opened.
        .task(id: LyricsModel.key(for: state) + (state.bundleIdentifier ?? "")) {
            await nowPlaying.refreshPlayerState()
        }
    }

    /// With the Mixer on, whether it already has a row for the playing app (and pins it first).
    private var mixerListsPlayer: Bool {
        guard let id = state.bundleIdentifier else { return false }
        return viewModel?.mixer.rows.contains { $0.id == id } == true
    }

    /// The player's own volume in the scrubber's slot, as wide as a Mixer row.
    @ViewBuilder
    private var volumeRow: some View {
        Group {
            if nowPlaying.appVolume != nil {
                VolumeControl(nowPlaying: nowPlaying, style: .row)
            } else {
                Color.clear
            }
        }
        .frame(height: Theme.Metrics.playerScrubber)
        .transition(.opacity)
    }

    /// Art, then the song over the artist, then the sound bars.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(
                image: nowPlaying.artwork,
                size: artworkSize,
                cornerRadius: inWidget ? Theme.Metrics.nestedRadius : Theme.Metrics.innerRadius
            )
            .mediaMatch("artwork", enabled: !inWidget)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.primary)
                Text(state.artist.isEmpty ? state.album : state.artist)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            .lineLimit(1)
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            // A widget keeps the room for the song instead.
            if !inWidget {
                EqualizerView(tint: nowPlaying.accent, scale: 1.2, isAnimating: state.isPlaying)
                    .mediaMatch("bars")
                    .padding(.top, 6)
            }
        }
        .frame(height: artworkSize)
    }

    /// Back, play or pause, and forward in the middle; the extras on either side.
    private var transport: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                if !isCompact {
                    IconButton(
                        systemName: "shuffle",
                        label: state.isShuffling ? "Shuffle On" : "Shuffle Off",
                        size: 12,
                        isSelected: state.isShuffling,
                        action: nowPlaying.toggleShuffle
                    )
                    IconButton(
                        systemName: state.repeatMode == .track ? "repeat.1" : "repeat",
                        label: repeatLabel,
                        size: 12,
                        isSelected: state.repeatMode != .off,
                        action: nowPlaying.cycleRepeat
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                IconButton(
                    systemName: "backward.fill", label: "Previous Track", size: 19,
                    hitSize: Theme.Metrics.playerTransport, action: nowPlaying.previousTrack
                )
                IconButton(
                    systemName: state.isPlaying ? "pause.fill" : "play.fill",
                    label: state.isPlaying ? "Pause" : "Play",
                    size: 26,
                    hitSize: Theme.Metrics.playerTransport,
                    action: nowPlaying.togglePlayPause
                )
                IconButton(
                    systemName: "forward.fill", label: "Next Track", size: 19,
                    hitSize: Theme.Metrics.playerTransport, action: nowPlaying.nextTrack
                )
            }

            HStack(spacing: 2) {
                if !isCompact, let isFavorite = nowPlaying.isFavorite {
                    IconButton(
                        systemName: isFavorite ? "heart.fill" : "heart",
                        label: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        size: 12,
                        isSelected: isFavorite,
                        action: nowPlaying.toggleFavorite
                    )
                }
                if !inWidget && !isPeek {
                    AudioOutputButton(
                        currentDeviceID: outputs.currentDevice?.id ?? outputs.defaultDeviceID,
                        isSelected: showsOutputs,
                        action: toggleOutputs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: Theme.Metrics.playerTransport)
    }

    private var repeatLabel: String {
        switch state.repeatMode {
        case .off: "Repeat Off"
        case .playlist: "Repeat All"
        case .track: "Repeat One"
        }
    }

    private func toggleOutputs() {
        if let viewModel, !isPeek {
            viewModel.toggleMediaOutputs()
        } else {
            if !showsOutputs { bluetooth.refresh() }
            withAnimation(Theme.Motion.resize) { showsOutputs.toggle() }
        }
    }
}

/// The player's own volume, for Music and Spotify. Separate from the Mac's output volume.
struct VolumeControl: View {
    enum Style {
        /// The Media tab: the app's name, a slider that fills the width, and the percent, in the Mixer's columns.
        case row
        /// The peek: a speaker glyph and a flexible slider, beside the output chip.
        case inline
    }

    let nowPlaying: NowPlayingModel
    var style: Style = .inline

    private var name: String { nowPlaying.player?.appName ?? "App" }
    private var volume: Double { nowPlaying.appVolume ?? 0 }

    var body: some View {
        switch style {
        case .row:
            HStack(spacing: 8) {
                Text(name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                    .frame(width: Theme.Metrics.mixerNameWidth, alignment: .leading)
                slider
                Text("\(Int((volume * 100).rounded()))%")
                    .font(Theme.Typography.numeral)
                    .foregroundStyle(Theme.Palette.secondary)
                    .frame(width: Theme.Metrics.mixerPercentWidth, alignment: .trailing)
            }
        case .inline:
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .accessibilityHidden(true)
                slider
            }
        }
    }

    private var slider: some View {
        IslandSlider(
            value: volume,
            tint: nowPlaying.accent,
            label: "\(name) Volume",
            onChange: { nowPlaying.previewAppVolume($0) },
            onCommit: { nowPlaying.setAppVolume($0) }
        )
    }
}

/// The line being sung, under the scrubber.
private struct LyricLineView: View {
    let nowPlaying: NowPlayingModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let line = LRC.text(at: nowPlaying.state.elapsed(at: context.date), in: nowPlaying.lyrics.lines)
            Text(line ?? "")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.lyricsRowHeight - Theme.Metrics.playerSpacing)
                .contentTransition(.opacity)
                .animation(Theme.Motion.resize, value: line)
                .accessibilityLabel(line.map { "Lyrics: \($0)" } ?? "Lyrics")
        }
    }
}

private struct ScrubberRow: View {
    let nowPlaying: NowPlayingModel

    var body: some View {
        let state = nowPlaying.state
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = state.elapsed(at: context.date)
            HStack(spacing: 8) {
                Text(formatTime(elapsed))
                    .frame(width: 30, alignment: .leading)
                IslandSlider(
                    value: state.duration > 0 ? elapsed / state.duration : 0,
                    tint: nowPlaying.accent,
                    label: "Playback Position",
                    valueDescription: "\(formatTime(elapsed)) of \(formatTime(state.duration))",
                    onCommit: { nowPlaying.seek(to: $0 * state.duration) }
                )
                .disabled(state.duration <= 0)
                Text("-" + formatTime(state.duration - elapsed))
                    .frame(width: 30, alignment: .trailing)
            }
            .font(Theme.Typography.numeral)
            .foregroundStyle(Theme.Palette.secondary)
        }
    }
}

/// Trailing half of the compact music activity: a play button while paused that grows into
/// bouncing bars once music plays. Clicking either toggles playback.
struct CompactPlaybackControl: View {
    let nowPlaying: NowPlayingModel

    private var isPlaying: Bool { nowPlaying.state.isPlaying }

    var body: some View {
        Button(action: nowPlaying.togglePlayPause) {
            ZStack {
                if isPlaying {
                    EqualizerView(tint: nowPlaying.accent)
                        .mediaMatch("bars")
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else {
                    Image(systemName: "play.fill")
                        .font(Theme.Typography.glyph)
                        .foregroundStyle(nowPlaying.accent)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .frame(width: Theme.Metrics.hitTarget, height: Theme.Metrics.hitTarget)
            .contentShape(Rectangle())
            .animation(Theme.Motion.resize, value: isPlaying)
        }
        .buttonStyle(IslandButtonStyle())
        .help(isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

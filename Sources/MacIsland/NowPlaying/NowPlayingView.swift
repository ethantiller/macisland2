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
    func mediaMatch(_ id: String) -> some View {
        modifier(MediaMatch(id: id))
    }
}

private struct MediaMatch: ViewModifier {
    let id: String

    @Environment(\.mediaNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
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
    /// The peek is narrower and only needs transport, so shuffle, repeat, and Favorite stay in the Media tab.
    var isPeek = false

    @State private var showsOutputs = false

    private var state: NowPlayingState { nowPlaying.state }
    private var artworkSize: CGFloat { isPeek ? Theme.Metrics.playerPeekArtwork : Theme.Metrics.playerArtwork }

    var body: some View {
        VStack(spacing: Theme.Metrics.playerSpacing) {
            header

            if showsOutputs {
                HStack(spacing: 12) {
                    if nowPlaying.appVolume != nil {
                        VolumeControl(nowPlaying: nowPlaying)
                    }
                    OutputPicker(outputs: outputs)
                }
                .frame(height: Theme.Metrics.playerScrubber)
                .transition(.opacity)
            } else {
                ScrubberRow(nowPlaying: nowPlaying)
                    .transition(.opacity)
            }

            transport

            if !nowPlaying.lyrics.lines.isEmpty {
                LyricLineView(nowPlaying: nowPlaying)
                    .transition(.opacity)
            }
        }
        .padding(.top, isPeek ? 0 : Theme.Metrics.playerTopInset)
        // Asked for while the view is visible, so a first Automation prompt comes from something the person opened.
        .task(id: LyricsModel.key(for: state) + (state.bundleIdentifier ?? "")) {
            await nowPlaying.refreshPlayerState()
        }
    }

    /// Art, then the song over the artist, then the sound bars.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(
                image: nowPlaying.artwork,
                size: artworkSize,
                cornerRadius: Theme.Metrics.innerRadius
            )
            .mediaMatch("artwork")

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

            EqualizerView(tint: nowPlaying.accent, scale: 1.2, isAnimating: state.isPlaying)
                .mediaMatch("bars")
                .padding(.top, 6)
        }
        .frame(height: artworkSize)
    }

    /// Back, play or pause, and forward in the middle; the extras on either side.
    private var transport: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                if !isPeek {
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
                if !isPeek, let isFavorite = nowPlaying.isFavorite {
                    IconButton(
                        systemName: isFavorite ? "heart.fill" : "heart",
                        label: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        size: 12,
                        isSelected: isFavorite,
                        action: nowPlaying.toggleFavorite
                    )
                }
                IconButton(
                    systemName: "airplayaudio",
                    label: "Audio Output and Volume",
                    isSelected: showsOutputs
                ) {
                    withAnimation(Theme.Motion.resize) { showsOutputs.toggle() }
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
}

/// The player's own volume, for Music and Spotify. Separate from the Mac's output volume.
private struct VolumeControl: View {
    let nowPlaying: NowPlayingModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiary)
                .accessibilityHidden(true)
            IslandSlider(
                value: nowPlaying.appVolume ?? 0,
                tint: nowPlaying.accent,
                label: "\(nowPlaying.player?.appName ?? "App") Volume",
                onChange: { nowPlaying.previewAppVolume($0) },
                onCommit: { nowPlaying.setAppVolume($0) }
            )
        }
        .frame(width: 130)
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

private struct OutputPicker: View {
    let outputs: AudioOutputs

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(outputs.devices) { device in
                    ChipButton(
                        title: device.name,
                        systemImage: device.systemImage,
                        isSelected: device.id == outputs.defaultDeviceID,
                        accessibilityLabel: "Play Audio on \(device.name)"
                    ) {
                        outputs.select(device)
                    }
                }
            }
        }
        .frame(height: Theme.Metrics.sliderHitHeight)
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

/// Bouncing bars tinted with the artwork accent. The bounce eases in from rest when the bars appear, so starting
/// playback reads as the music "waking up". `scale` sizes them (the peek and the Media tab use bigger ones), and
/// without `isAnimating` they rest, dimmed.
struct EqualizerView: View {
    let tint: Color
    var scale: CGFloat = 1
    var isAnimating = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt = Date()

    private let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]
    private let phases: [Double] = [0, 1.3, 2.1, 0.7]
    private let restingHeights: [CGFloat] = [6, 10, 7, 9]

    private var isMoving: Bool { isAnimating && !reduceMotion }

    var body: some View {
        TimelineView(.animation(paused: !isMoving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let ramp = easeInOut(min(max(context.date.timeIntervalSince(appearedAt) / 0.45, 0), 1))
            HStack(spacing: 2 * scale) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: 3 * scale, height: barHeight(i, time: t, ramp: ramp) * scale)
                }
            }
            .frame(height: 14 * scale)
        }
        .opacity(isAnimating ? 1 : 0.45)
        .onAppear { appearedAt = Date() }
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int, time: TimeInterval, ramp: Double) -> CGFloat {
        guard isMoving else { return restingHeights[index] }
        return 3 + CGFloat(ramp) * (1 + 10 * abs(sin(time * speeds[index] + phases[index])))
    }

    private func easeInOut(_ x: Double) -> Double {
        x * x * (3 - 2 * x)
    }
}

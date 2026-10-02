import SwiftUI

/// Hover: the top live activity at full size, without the tab strip. A click opens the island.
struct PeekContent: View {
    let viewModel: IslandViewModel

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            if viewModel.showsActivityChoice { ActivityChoiceRow(viewModel: viewModel) }
            content
        }
        .frame(height: viewModel.peekContentHeight, alignment: .top)
        .padding(.horizontal, ScreenGeometry.topFlare + Theme.Metrics.margin)
        .padding(.top, viewModel.geometry.notchSize.height + Theme.Metrics.contentTopGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        Group {
            switch viewModel.peekActivity {
            case .media:
                NowPlayingView(
                    nowPlaying: viewModel.nowPlaying, outputs: viewModel.outputs, bluetooth: viewModel.bluetooth,
                    isPeek: true, peekOutputList: Binding(
                        get: { viewModel.showsPeekOutputList },
                        set: { viewModel.showsPeekOutputList = $0 }))
            case .timer, .pomodoro, .stopwatch:
                ClockPeekView(viewModel: viewModel)
            case .agent:
                AgentPeekView(agents: viewModel.agents)
            case .countdown(let event):
                CountdownPeekView(event: event, agenda: viewModel.agenda)
            case .recording(.voice):
                VoicePeekView(viewModel: viewModel)
            default:
                IdlePeekView(viewModel: viewModel)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Hover with nothing live: the day at a glance, and the everyday controls within reach.
struct IdlePeekView: View {
    let viewModel: IslandViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                DateInline()
                if viewModel.settings.isOn(.weather), let conditions = viewModel.weather.conditions {
                    WeatherGlance(conditions: conditions)
                }
                Spacer(minLength: 0)
                if let next = viewModel.agenda.next {
                    UpNextLabel(item: next, emptyTitle: "", settings: viewModel.settings)
                } else {
                    MacBatteryGlance()
                }
            }
            .frame(height: 44)

            HStack(spacing: 12) {
                if viewModel.settings.isOn(.tools) { QuickToolsRow(viewModel: viewModel) }
                Spacer(minLength: 0)
                if viewModel.settings.isOn(.clock) { QuickTimerChips(viewModel: viewModel, showsPomodoro: false) }
            }
            .frame(height: Theme.Metrics.homeQuickHeight)
        }
    }
}

/// Hover while an event is about to start: its title, when it starts, the time left, and Join when it has a call link.
struct CountdownPeekView: View {
    let event: AgendaItem
    let agenda: AgendaMonitor

    var body: some View {
        HStack(spacing: 14) {
            Glyph(systemName: "calendar", tint: Theme.Tint.clock)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                Text(event.date.formatted(date: .omitted, time: .shortened))
                    .font(Theme.Typography.numeral)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            Spacer(minLength: 8)
            CompactCountdownText(item: event, agenda: agenda)
            if let url = event.joinURL {
                ChipButton(title: "Join", systemImage: "video.fill", isProminent: true) { MeetingLink.join(url) }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Hover while recording a voice note: how long, how loud, and Stop. The meter is read only while this is showing.
struct VoicePeekView: View {
    let viewModel: IslandViewModel

    private var voice: VoiceRecorder { viewModel.voice }

    var body: some View {
        HStack(spacing: 14) {
            Glyph(systemName: "waveform", tint: Theme.Tint.working)
                .symbolEffect(.pulse)
            if let since = voice.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(formatTime(context.date.timeIntervalSince(since)))
                        .font(Theme.Typography.largeNumeral)
                        .foregroundStyle(Theme.Palette.primary)
                }
            }
            TimelineView(.animation(minimumInterval: 0.1)) { _ in
                LevelMeterBar(level: Double(voice.level))
            }
            .frame(height: 6)
            ChipButton(title: "Stop", systemImage: "stop.fill", isProminent: true) { viewModel.toggleVoiceNote() }
        }
        .frame(maxHeight: .infinity)
    }
}

/// A thin bar that fills with the input level.
private struct LevelMeterBar: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.fill)
                Capsule().fill(Theme.Tint.working)
                    .frame(width: max(6, proxy.size.width * min(max(level, 0), 1)))
            }
        }
        .accessibilityHidden(true)
    }
}

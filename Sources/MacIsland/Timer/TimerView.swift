import Charts
import SwiftUI

/// Timer, stopwatch, and Pomodoro share one tab. A timer that hasn't been set yet gets the dial; otherwise
/// a ring on the leading side, and on the trailing side the mode picker with play and cancel beside it, and
/// presets or lap times below. Pomodoro adds its streak and a 7-day chart underneath.
struct ClockView: View {
    let viewModel: IslandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.clockMode == .timer, !viewModel.timer.isActive {
                TimerSetter(viewModel: viewModel)
                    .frame(height: Theme.Metrics.timerSetter)
            } else {
                HStack(alignment: .center, spacing: Theme.Metrics.margin) {
                    switch viewModel.clockMode {
                    case .timer: TimerRing(timer: viewModel.timer)
                    case .stopwatch: StopwatchRing(stopwatch: viewModel.stopwatch)
                    case .pomodoro: PomodoroRing(pomodoro: viewModel.pomodoro)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 4) {
                            ClockModePicker(viewModel: viewModel)
                            Spacer(minLength: 0)
                            switch viewModel.clockMode {
                            case .timer: TimerActions(timer: viewModel.timer)
                            case .stopwatch: StopwatchActions(stopwatch: viewModel.stopwatch)
                            case .pomodoro: PomodoroActions(pomodoro: viewModel.pomodoro)
                            }
                        }

                        switch viewModel.clockMode {
                        case .timer: TimerPresets(timer: viewModel.timer)
                        case .stopwatch: StopwatchLaps(stopwatch: viewModel.stopwatch)
                        case .pomodoro: PomodoroStatus(pomodoro: viewModel.pomodoro)
                        }
                    }
                }
                .frame(height: Theme.Metrics.clockRing)
            }

            if viewModel.clockMode == .pomodoro {
                PomodoroChart(pomodoro: viewModel.pomodoro)
                    .frame(height: Theme.Metrics.pomodoroStatsHeight - 10)
                    .transition(.opacity)
            }
        }
    }
}

private struct ClockModePicker: View {
    let viewModel: IslandViewModel

    var body: some View {
        SegmentedChoice(
            options: ClockMode.allCases,
            selection: viewModel.clockMode,
            title: \.rawValue,
            onSelect: viewModel.setClockMode
        )
        .frame(width: 230)
    }
}

// MARK: Pomodoro

private struct PomodoroRing: View {
    let pomodoro: PomodoroModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = pomodoro.remaining(at: context.date).rounded(.up)
            ZStack {
                ProgressRing(progress: pomodoro.progress(at: context.date), tint: Theme.Tint.clock, lineWidth: 4)
                Text(formatTime(remaining))
                    .font(Theme.Typography.largeNumeral)
                    .foregroundStyle(Theme.Palette.primary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: remaining)
            }
            .frame(width: Theme.Metrics.clockRing, height: Theme.Metrics.clockRing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(pomodoro.phase.title) Time Remaining")
            .accessibilityValue(formatTime(remaining))
        }
    }
}

private struct PomodoroActions: View {
    let pomodoro: PomodoroModel

    var body: some View {
        HStack(spacing: 0) {
            IconButton(
                systemName: pomodoro.isRunning ? "pause.fill" : "play.fill",
                label: pomodoro.isRunning ? "Pause Pomodoro" : "Start Pomodoro",
                size: 16,
                action: pomodoro.toggle
            )
            IconButton(systemName: "forward.end.fill", label: "Skip to Next", size: 12) { pomodoro.skip() }
                .opacity(pomodoro.isActive ? 1 : 0.4)
                .disabled(!pomodoro.isActive)
            IconButton(systemName: "xmark", label: "Reset Pomodoro", action: pomodoro.reset)
                .opacity(pomodoro.isActive || pomodoro.focusInCycle > 0 ? 1 : 0.4)
                .disabled(!pomodoro.isActive && pomodoro.focusInCycle == 0)
        }
    }
}

/// What phase it is, how far into the cycle, and the streak.
private struct PomodoroStatus: View {
    let pomodoro: PomodoroModel

    var body: some View {
        HStack(spacing: 10) {
            Text(pomodoro.phase.title)
                .font(Theme.Typography.bodyEmphasized)
                .foregroundStyle(Theme.Palette.primary)
            Text(
                "\(min(pomodoro.focusInCycle + (pomodoro.phase == .focus ? 1 : 0), pomodoro.plan.sessions)) of \(pomodoro.plan.sessions)"
            )
            .font(Theme.Typography.numeral)
            .foregroundStyle(Theme.Palette.secondary)
            if pomodoro.streak > 0 {
                Label("\(pomodoro.streak) day streak", systemImage: "flame.fill")
                    .font(Theme.Typography.numeral)
                    .foregroundStyle(Theme.Tint.clock)
            }
        }
        .frame(height: 24)
        .accessibilityElement(children: .combine)
    }
}

/// Sessions finished on each of the last seven days.
private struct PomodoroChart: View {
    let pomodoro: PomodoroModel

    var body: some View {
        let days = pomodoro.history.lastSevenDays(asOf: Date())
        let top = max(days.map(\.count).max() ?? 0, 4)
        Chart(days, id: \.date) { day in
            // A faint track behind each day, so days without sessions still read as part of the chart.
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Track", top), width: .fixed(18))
                .foregroundStyle(Theme.Palette.fill)
                .cornerRadius(3)
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Sessions", day.count), width: .fixed(18))
                .foregroundStyle(Theme.Tint.clock)
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...top)
        .accessibilityLabel("Focus sessions, last seven days")
        .accessibilityValue(days.map { "\($0.count)" }.joined(separator: ", "))
    }
}

// MARK: Timer

private struct TimerRing: View {
    let timer: TimerModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = timer.remaining(at: context.date).rounded(.up)
            ZStack {
                ProgressRing(progress: timer.progress(at: context.date), tint: Theme.Tint.clock, lineWidth: 4)
                Text(formatTime(remaining))
                    .font(Theme.Typography.largeNumeral)
                    .foregroundStyle(Theme.Palette.primary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: remaining)
            }
            .frame(width: Theme.Metrics.clockRing, height: Theme.Metrics.clockRing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time Remaining")
            .accessibilityValue(formatTime(remaining))
        }
    }
}

private struct TimerPresets: View {
    let timer: TimerModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach([1, 5, 10, 25], id: \.self) { minutes in
                ChipButton(
                    title: "\(minutes)m",
                    isSelected: timer.duration == TimeInterval(minutes * 60) && timer.isActive,
                    accessibilityLabel: "Start \(minutes) Minute Timer"
                ) {
                    timer.start(minutes: minutes)
                }
            }
            ChipButton(title: "+1m", accessibilityLabel: "Add 1 Minute", action: timer.addMinute)
        }
    }
}

private struct TimerActions: View {
    let timer: TimerModel

    var body: some View {
        HStack(spacing: 0) {
            IconButton(
                systemName: timer.isRunning ? "pause.fill" : "play.fill",
                label: timer.isRunning ? "Pause Timer" : "Start Timer",
                size: 16,
                action: timer.toggle
            )
            IconButton(systemName: "xmark", label: "Cancel Timer", action: timer.reset)
                .opacity(timer.isActive ? 1 : 0.4)
                .disabled(!timer.isActive)
        }
    }
}

// MARK: Setting a timer

/// Setting a timer: the mode picker and three quick lengths, the minute dial, then Start and the length it
/// will run for.
private struct TimerSetter: View {
    let viewModel: IslandViewModel

    private static let quickMinutes = [1, 5, 10]

    var body: some View {
        let timer = viewModel.timer
        let minutes = Int((timer.duration / 60).rounded())
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ClockModePicker(viewModel: viewModel)
                Spacer(minLength: 0)
                ForEach(Self.quickMinutes, id: \.self) { preset in
                    ChipButton(
                        title: "\(preset)m",
                        isSelected: minutes == preset,
                        accessibilityLabel: "\(preset) Minutes"
                    ) {
                        withAnimation(Theme.Motion.track) { timer.setDuration(minutes: preset) }
                    }
                }
            }
            .frame(height: Theme.Metrics.clockHeaderHeight)

            TimerDial(viewModel: viewModel)
                .frame(height: Theme.Metrics.timerDial)

            HStack(spacing: 10) {
                ChipButton(title: "Start Timer", isProminent: true, action: timer.toggle)
                Spacer(minLength: 0)
                Text(formatTime(timer.duration))
                    .font(Theme.Typography.largeNumeral)
                    .foregroundStyle(Theme.Tint.clock)
                    .contentTransition(.numericText())
            }
            .frame(height: Theme.Metrics.hitTarget)
        }
    }
}

/// A ruler of minutes that slides under a fixed marker. Drag it or scroll it sideways and the ruler follows
/// the pointer; tap a tick and it glides under the marker. The ruler fades out toward both edges.
private struct TimerDial: View {
    let viewModel: IslandViewModel
    @Environment(\.isFloatingWindow) private var isFloating

    var body: some View {
        let minutes = viewModel.timer.durationMinutes
        GeometryReader { geometry in
            let width = geometry.size.width
            DialRuler(position: viewModel.dialPosition ?? Double(minutes))
                .frame(width: width, height: Theme.Metrics.timerDial)
                .edgeFade(.horizontal, fraction: Theme.Metrics.dialFade)
                .overlay(alignment: .bottom) { DialMarker() }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { viewModel.scrubDial(translation: $0.translation.width) }
                        .onEnded { _ in viewModel.endDialScrub() }
                        .exclusively(
                            before: SpatialTapGesture().onEnded { tap in
                                viewModel.setDial(
                                    to: DialScrubber.minute(
                                        atX: tap.location.x, markerX: width / 2, position: Double(minutes)))
                            })
                )
                .background { if isFloating { DialScrollCatcher(viewModel: viewModel) } }
        }
        .accessibilityElement()
        .accessibilityLabel("Timer Length")
        .accessibilityValue(spokenMinutes(minutes))
        .accessibilityAdjustableAction { direction in
            viewModel.stepDial(direction == .increment ? 1 : -1)
        }
    }

    private func spokenMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        let hourText = hours == 0 ? "" : "\(hours) \(hours == 1 ? "hour" : "hours")"
        let minuteText = rest == 0 && hours > 0 ? "" : "\(rest) \(rest == 1 ? "minute" : "minutes")"
        return [hourText, minuteText].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The fixed triangle under the chosen minute.
private struct DialMarker: View {
    var body: some View {
        Image(systemName: "arrowtriangle.up.fill")
            .resizable()
            .scaledToFit()
            .frame(width: Theme.Metrics.dialMarker, height: Theme.Metrics.dialMarker)
            .foregroundStyle(Theme.Tint.clock)
    }
}

/// The ticks and minute numbers, drawn in one pass for whatever `position` is under the center. `Animatable`,
/// so a tap or a settle glides instead of jumping.
private struct DialRuler: View, Animatable {
    var position: Double

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let metrics = Theme.Metrics.self
            let markerX = size.width / 2
            let tickBottom = metrics.dialLabelHeight + metrics.dialRowSpacing + metrics.dialMajorTick
            for minute in DialScrubber.visibleRange(position: position, width: size.width) {
                let x = markerX + CGFloat(Double(minute) - position) * metrics.dialMinuteSpacing
                let isFifth = minute % 5 == 0
                let height = isFifth ? metrics.dialMajorTick : metrics.dialMinorTick
                let tick = CGRect(
                    x: x - metrics.dialTickWidth / 2, y: tickBottom - height, width: metrics.dialTickWidth,
                    height: height)
                context.fill(
                    Path(roundedRect: tick, cornerRadius: metrics.dialTickWidth / 2),
                    with: .style(isFifth ? Theme.Palette.secondary : Theme.Palette.tertiary))
                if isFifth {
                    let label = context.resolve(
                        Text("\(minute)").font(Theme.Typography.numeral).foregroundStyle(Theme.Palette.secondary))
                    context.draw(label, at: CGPoint(x: x, y: metrics.dialLabelHeight / 2), anchor: .center)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Menu-bar and torn-off Clock windows don't pass through the island's mouse tracker, so a scroll over their
/// dial is caught here and goes to the same view-model calls. The island itself never installs it.
private struct DialScrollCatcher: NSViewRepresentable {
    let viewModel: IslandViewModel

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.viewModel = viewModel }

    final class CatcherView: NSView {
        var viewModel: IslandViewModel?
        private var routing = ScrollRouting()
        private var settleTask: Task<Void, Never>?

        override func scrollWheel(with event: NSEvent) {
            guard let viewModel else { return super.scrollWheel(with: event) }
            let sample = ScrollSample(
                dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                isPrecise: event.hasPreciseScrollingDeltas, isInverted: event.isDirectionInvertedFromDevice,
                isBegan: event.phase.contains(.began), isMomentum: !event.momentumPhase.isEmpty)
            switch routing.route(sample, overDial: true) {
            case .scrubDial(let dx):
                viewModel.scrubDial(byFingerDX: dx)
                settleTask?.cancel()
                settleTask = Task { [weak viewModel] in
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled else { return }
                    viewModel?.endDialScrub()
                }
            case .stepDial(let step):
                viewModel.stepDial(step)
            case .swipe, nil:
                super.scrollWheel(with: event)
            }
        }
    }
}

// MARK: Stopwatch

private struct StopwatchRing: View {
    let stopwatch: StopwatchModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = stopwatch.elapsed(at: context.date)
            ZStack {
                ProgressRing(
                    progress: elapsed.truncatingRemainder(dividingBy: 60) / 60,
                    tint: Theme.Tint.clock,
                    lineWidth: 4
                )
                Text(formatStopwatch(elapsed))
                    .font(Theme.Typography.largeNumeral)
                    .foregroundStyle(Theme.Palette.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .frame(width: Theme.Metrics.clockRing, height: Theme.Metrics.clockRing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stopwatch")
            .accessibilityValue(formatTime(elapsed))
        }
    }
}

private struct StopwatchLaps: View {
    let stopwatch: StopwatchModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            HStack(spacing: 10) {
                Text(stopwatch.laps.isEmpty ? "Lap 1" : "Lap \(stopwatch.laps.count + 1)")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                Text(formatStopwatch(stopwatch.currentLap(at: context.date)))
                    .font(Theme.Typography.compactNumeral)
                    .foregroundStyle(Theme.Palette.primary)
                if let last = stopwatch.laps.last {
                    Text("Last " + formatStopwatch(last))
                        .font(Theme.Typography.numeral)
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
            .frame(height: 24)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct StopwatchActions: View {
    let stopwatch: StopwatchModel

    var body: some View {
        HStack(spacing: 0) {
            IconButton(
                systemName: stopwatch.isRunning ? "pause.fill" : "play.fill",
                label: stopwatch.isRunning ? "Stop Stopwatch" : "Start Stopwatch",
                size: 16
            ) {
                stopwatch.toggle()
            }
            if stopwatch.isRunning {
                IconButton(systemName: "flag.fill", label: "Lap") { stopwatch.lap() }
            } else {
                IconButton(systemName: "xmark", label: "Reset Stopwatch", action: stopwatch.reset)
                    .opacity(stopwatch.isActive ? 1 : 0.4)
                    .disabled(!stopwatch.isActive)
            }
        }
    }
}

// MARK: Compact

/// Countdown text shown beside the notch while a timer runs.
struct CompactTimerText: View {
    let timer: TimerModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date).rounded(.up)
            Text(formatTime(remaining))
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Tint.clock)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: remaining)
        }
        .accessibilityLabel("Timer")
    }
}

/// The time left until an event starts, beside the notch in the hour before it does. Ticks once a second only while it shows, and
/// asks the agenda to look again when the event starts, so the activity ends then.
struct CompactCountdownText: View {
    let item: AgendaItem
    let agenda: AgendaMonitor

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(item.date.timeIntervalSince(context.date), 0).rounded(.up)
            Text(formatTime(remaining))
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Tint.clock)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: remaining)
        }
        .task(id: item.id) {
            let wait = item.date.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            agenda.refresh()
        }
        .accessibilityLabel("Countdown to \(item.title)")
    }
}

/// Small ring beside the notch while a timer runs.
struct CompactTimerRing: View {
    let timer: TimerModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ProgressRing(progress: timer.progress(at: context.date), tint: Theme.Tint.clock, lineWidth: 2.5)
                .frame(width: 14, height: 14)
        }
    }
}

struct CompactStopwatchText: View {
    let stopwatch: StopwatchModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = stopwatch.elapsed(at: context.date).rounded(.down)
            Text(formatTime(elapsed))
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Tint.clock)
                .contentTransition(.numericText())
                .animation(.default, value: elapsed)
        }
        .accessibilityLabel("Stopwatch")
    }
}

/// Small ring beside the notch while a Pomodoro session runs.
struct CompactPomodoroRing: View {
    let pomodoro: PomodoroModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ProgressRing(progress: pomodoro.progress(at: context.date), tint: Theme.Tint.clock, lineWidth: 2.5)
                .frame(width: 14, height: 14)
        }
        .accessibilityLabel("Pomodoro")
    }
}

struct CompactPomodoroText: View {
    let pomodoro: PomodoroModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = pomodoro.remaining(at: context.date).rounded(.up)
            Text(formatTime(remaining))
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Tint.clock)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: remaining)
        }
        .accessibilityLabel("Pomodoro \(pomodoro.phase.title)")
    }
}

/// The running timer, stopwatch, or Pomodoro in the narrower peek: its ring and controls, without the mode
/// picker or the presets the full Clock tab has.
struct ClockPeekView: View {
    let viewModel: IslandViewModel

    var body: some View {
        HStack(spacing: Theme.Metrics.margin) {
            switch viewModel.compactActivity {
            case .pomodoro:
                PomodoroRing(pomodoro: viewModel.pomodoro)
                PomodoroPeekDetails(pomodoro: viewModel.pomodoro)
            case .stopwatch:
                StopwatchRing(stopwatch: viewModel.stopwatch)
                StopwatchPeekDetails(stopwatch: viewModel.stopwatch)
            default:
                TimerRing(timer: viewModel.timer)
                TimerPeekDetails(timer: viewModel.timer)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The Pomodoro's peek: which session, the streak, the controls, and what comes next.
private struct PomodoroPeekDetails: View {
    let pomodoro: PomodoroModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(pomodoro.phase.title)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                Text(
                    "\(min(finishedIncludingThis, pomodoro.plan.sessions)) of \(pomodoro.plan.sessions)"
                )
                .font(Theme.Typography.numeral)
                .foregroundStyle(Theme.Palette.secondary)
                if pomodoro.streak > 0 {
                    Label("\(pomodoro.streak) day streak", systemImage: "flame.fill")
                        .font(Theme.Typography.numeral)
                        .foregroundStyle(Theme.Tint.clock)
                }
            }
            HStack(spacing: 4) {
                PomodoroActions(pomodoro: pomodoro)
                Text(nextText)
                    .font(Theme.Typography.numeral)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .lineLimit(1)
    }

    /// Focus sessions done in this cycle, counting the one in progress.
    private var finishedIncludingThis: Int {
        pomodoro.focusInCycle + (pomodoro.phase == .focus ? 1 : 0)
    }

    /// What follows this session, or that the cycle ends with it.
    private var nextText: String {
        guard
            let next = PomodoroModel.next(
                after: pomodoro.phase, focusFinished: finishedIncludingThis, sessions: pomodoro.plan.sessions)
        else {
            return "Last one"
        }
        return "Then \(next.title)"
    }
}

/// The stopwatch's peek: the lap in progress and the last one, with the controls.
private struct StopwatchPeekDetails: View {
    let stopwatch: StopwatchModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Stopwatch")
                        .font(Theme.Typography.bodyEmphasized)
                        .foregroundStyle(Theme.Palette.primary)
                    Text("Lap \(stopwatch.laps.count + 1)  \(formatStopwatch(stopwatch.currentLap(at: context.date)))")
                        .font(Theme.Typography.numeral)
                        .foregroundStyle(Theme.Palette.secondary)
                }
                HStack(spacing: 4) {
                    StopwatchActions(stopwatch: stopwatch)
                    if let last = stopwatch.laps.last {
                        Text("Last \(formatStopwatch(last))")
                            .font(Theme.Typography.numeral)
                            .foregroundStyle(Theme.Palette.secondary)
                    }
                }
            }
            .lineLimit(1)
        }
    }
}

/// The timer's peek: when it ends, and the controls with quick extensions, so the peek uses its width.
private struct TimerPeekDetails: View {
    let timer: TimerModel

    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Timer")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                Text(timer.endDate.map { "Ends \($0.formatted(Self.timeFormat))" } ?? "Paused")
                    .font(Theme.Typography.numeral)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            HStack(spacing: 4) {
                TimerActions(timer: timer)
                ChipButton(title: "+1m", accessibilityLabel: "Add 1 Minute") { timer.add(minutes: 1) }
                ChipButton(title: "+5m", accessibilityLabel: "Add 5 Minutes") { timer.add(minutes: 5) }
            }
        }
    }
}

/// Keep Awake's time left beside the notch, updated once a minute while it shows. White: it is a state, not a clock being timed.
struct CompactKeepAwakeText: View {
    let keepAwake: KeepAwake

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let end = keepAwake.endsAt {
                Text(KeepAwakeTime.text(remaining: end.timeIntervalSince(context.date)))
                    .font(Theme.Typography.compactNumeral)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("Keep Awake")
    }
}

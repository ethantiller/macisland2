import SwiftUI

// Pieces the idle peek uses (Home's own widgets are in HomeWidgets.swift): the date, what is next, the
// everyday tools, and the timer.

/// The date and month in one line, for the idle peek.
struct DateInline: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(Date().formatted(.dateTime.day()))
                .font(Theme.Typography.largeNumeral)
                .foregroundStyle(Theme.Palette.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                Text(Date().formatted(.dateTime.month(.wide)))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Up next

/// Icon, title, and when. Without an item it says so, quietly.
struct UpNextLabel: View {
    let item: AgendaItem?
    let emptyTitle: String
    /// Reads the time-left and countdown choices, and offers Add Countdown on an event that hasn't started. Nil in a sample.
    var settings: AppSettings?
    private var showsTimeLeft: Bool { settings?.showsTimeLeft ?? false }

    var body: some View {
        if let item {
            // Re-evaluated every 30s so "in 5 min" keeps counting down.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 8) {
                    Image(systemName: item.kind == .event ? "calendar" : "checklist")
                        .font(Theme.Typography.glyph)
                        .foregroundStyle(Theme.Palette.primary)
                        .frame(width: Theme.Metrics.glyphSlot)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(Theme.Typography.bodyEmphasized)
                            .foregroundStyle(Theme.Palette.primary)
                        Text(
                            AgendaRules.timeText(for: item, now: context.date, showsTimeLeft: showsTimeLeft) + (item.joinURL == nil ? "" : " · Join")
                        )
                        .font(Theme.Typography.numeral)
                        .foregroundStyle(Theme.Palette.secondary)
                    }
                    .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .contextMenu { countdownMenu(for: item, now: context.date) }
            }
        } else {
            Label(emptyTitle, systemImage: "checkmark.circle")
                .font(Theme.Typography.bodyEmphasized)
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(1)
        }
    }
}

extension UpNextLabel {
    /// Add Countdown or Remove Countdown, for an event with a start time that hasn't started, while Count Down to Every Event is off.
    @ViewBuilder
    fileprivate func countdownMenu(for item: AgendaItem, now: Date) -> some View {
        if let settings, !settings.countsDownToEveryEvent, settings.isOn(.calendar),
            AgendaRules.canCountDown(item, now: now)
        {
            if settings.hasCountdown(item.id) {
                Button("Remove Countdown") { settings.setCountdown(for: item, false) }
            } else {
                Button("Add Countdown") { settings.setCountdown(for: item, true) }
            }
        }
    }
}

// MARK: Quick controls

/// The first few pinned tools as round buttons. On is a white fill with a black glyph.
struct QuickToolsRow: View {
    let viewModel: IslandViewModel
    var count = 4

    var body: some View {
        let catalog = ToolCatalog(viewModel: viewModel)
        HStack(spacing: 8) {
            ForEach(viewModel.settings.visiblePinned.prefix(count)) { id in
                QuickToolButton(item: catalog.item(for: id))
            }
        }
    }
}

struct QuickToolButton: View {
    let item: ToolItem
    var size: CGFloat = Theme.Metrics.homeQuickHeight
    var restingFill: SurfaceInk = Theme.Palette.fill
    var hoverFill: SurfaceInk = Theme.Palette.fillHover

    @State private var isHovering = false

    var body: some View {
        Button(action: item.action) {
            Image(systemName: item.systemImage)
                .font(Theme.Typography.glyph)
                .foregroundStyle(item.isOn ? Theme.Palette.inverse : Theme.Palette.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(
                    item.isOn ? Theme.Palette.primary : (isHovering ? hoverFill : restingFill),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
        .disabled(!item.isAvailable)
        .opacity(item.isAvailable ? 1 : 0.4)
        .task(id: item.id) { await item.watch?() }
        .onHover { isHovering = $0 }
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item.isOn ? .isSelected : [])
    }
}

/// Start a timer in one tap, or see the one that's running.
struct QuickTimerChips: View {
    let viewModel: IslandViewModel
    /// The peek is narrower, so it leaves Pomodoro to Home and the Clock tab.
    var showsPomodoro = true

    var body: some View {
        HStack(spacing: 6) {
            if viewModel.timer.isActive {
                running(CompactTimerText(timer: viewModel.timer), mode: .timer)
            } else if viewModel.pomodoro.isActive {
                running(CompactPomodoroText(pomodoro: viewModel.pomodoro), mode: .pomodoro)
            } else if viewModel.stopwatch.isActive {
                running(CompactStopwatchText(stopwatch: viewModel.stopwatch), mode: .stopwatch)
            } else {
                if !showsPomodoro {
                    ChipButton(title: "1m", accessibilityLabel: "Start 1 Minute Timer") {
                        viewModel.timer.start(minutes: 1)
                    }
                }
                ChipButton(title: "5m", accessibilityLabel: "Start 5 Minute Timer") {
                    viewModel.timer.start(minutes: 5)
                }
                ChipButton(title: "25m", accessibilityLabel: "Start 25 Minute Timer") {
                    viewModel.timer.start(minutes: 25)
                }
                if showsPomodoro {
                    ChipButton(title: "Pomodoro", systemImage: "brain.head.profile") { viewModel.pomodoro.toggle() }
                }
            }
        }
    }

    /// A running clock, shown as its time. Opens the Clock tab.
    private func running<Content: View>(_ time: Content, mode: ClockMode) -> some View {
        Button {
            viewModel.openClock(mode)
        } label: {
            time
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
                .background(Theme.Palette.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(IslandButtonStyle())
    }
}

// MARK: This Mac

/// This Mac's battery, in a glance.
struct MacBatteryGlance: View {
    @State private var reading = BatteryMonitor.readInternalBattery()

    var body: some View {
        if let reading {
            Label(
                "\(reading.percent)%", systemImage: BatteryMonitor.symbol(percent: reading.percent, onAC: reading.onAC)
            )
            .font(Theme.Typography.compactNumeral)
            .foregroundStyle(Theme.Palette.primary)
            .accessibilityLabel("Battery \(reading.percent) percent\(reading.onAC ? ", charging" : "")")
        }
    }
}

import AppKit
import SwiftUI

/// The first-run guide's content: a header, the stage (an island you can use, drawn from sample data), the step's words, its detail,
/// and the footer. No native controls: every button is `ChipButton` or `IconButton`. Drawn on floating glass by
/// `OnboardingRoot`, so ink is `Theme.Palette` with `\.islandSurface = .glass`.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    /// The island in this window: what the person practises on, and what the practice checks watch.
    private var island: IslandViewModel { model.stageIsland }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            header
            stage
            words
            footer
        }
        .frame(width: Theme.Metrics.guideWidth - 2 * Theme.Metrics.floatPadding)
        .onChange(of: model.step.id) { announce() }
        // The practice checks watch the stage island. No timers: each change is reported as it happens.
        .onChange(of: island.state) { observeIsland() }
        .onChange(of: island.selectedTab) { _, tab in
            observeIsland()
            model.stageChangedTab(tab)
        }
        .onChange(of: island.isFileDragActive) { observeIsland() }
    }

    private func observeIsland() {
        model.observe(PracticeGoal.Island(island))
    }

    // MARK: Header and stage

    private var header: some View {
        HStack {
            StepDots(count: model.flow.count, current: model.flow.index)
            Spacer()
        }
        .frame(height: Theme.Metrics.hitTarget)
    }

    private var stage: some View {
        PreviewBand(model: model.preview)
            // The stage is an island you can use: hover, click, swipe, drag a file over it, and the keys.
            .stageInput(island, isOn: model.step.stageIsInteractive)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stageLabel)
    }

    /// What the stage shows right now. The island changes as it is used, so this reads it, not the step's starting context.
    private var stageLabel: String {
        if model.preview.context.presentation == .menuBar { return "The menu bar, with a module\u{2019}s window open." }
        switch island.presentation {
        case .expanded: return "The island, open on \(island.selectedTab.title)."
        case .compact: return "The island, folded into the notch."
        case .peek: return "The island, peeking."
        case .banner: return "The island, showing a banner."
        }
    }

    // MARK: Words and detail

    private var words: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
                Text(model.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(model.copy)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(3, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                detail
                    .frame(
                        maxWidth: .infinity, minHeight: Theme.Metrics.guideDetailHeight,
                        maxHeight: Theme.Metrics.guideDetailHeight, alignment: .topLeading)
            }
            .id(model.step.id)
            .transition(Theme.Motion.content)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// What sits under the words. Every step has this much room, so the window never changes height.
    @ViewBuilder private var detail: some View {
        switch model.step.id {
        case .peek, .open, .tabs, .close, .drop:
            practiceDetail
        case .modules:
            modulesDetail
        case .calendars, .reminders, .bluetooth, .downloads, .camera, .microphone, .screenRecording, .accessibility,
            .focus, .automation:
            permissionDetail
        case .finish:
            finishDetail
        default:
            EmptyView()
        }
    }

    /// Open at Login, and the permissions still to allow: Done waits for them, and a name goes back to its step.
    private var finishDetail: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            ChipButton(
                title: "Open at Login", systemImage: "power", isSelected: model.launchAtLogin
            ) { model.toggleLaunchAtLogin() }
            if !model.stillNeeded.isEmpty { stillNeeded }
        }
        // Login Items can be changed in System Settings while the guide is open, and so can a permission.
        .onAppear {
            model.refreshLaunchAtLogin()
            model.access.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.access.refresh()
        }
    }

    private var stillNeeded: some View {
        let names = model.stillNeeded
        return FlowLayout(spacing: 4) {
            Text("Still needed:")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondary)
            ForEach(Array(names.enumerated()), id: \.element) { index, kind in
                HStack(spacing: 0) {
                    Button {
                        withAnimation(Theme.Motion.resize) { model.go(to: GuideStepID(kind)) }
                    } label: {
                        Text(kind.title).underline()
                    }
                    .buttonStyle(IslandButtonStyle())
                    .accessibilityLabel("Go to \(kind.title)")
                    Text(index == names.count - 1 ? "." : ",")
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondary)
            }
        }
    }

    /// The permission this step is about: its glyph and state, what that means, and what to do when it is off. The buttons that ask
    /// are in the footer, so every step has the same layout.
    private var permissionDetail: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            if let kind = model.accessKind, let state = model.accessState {
                PermissionStatus(kind: kind, state: state, isAsking: model.access.asking == kind)
                Text(GuideCopy.outcome(kind, state: state, offItem: model.offItem?.title))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if kind == .screenRecording, state == .denied {
                    ChipButton(title: "Reopen MacIsland") { AppRelaunch.relaunch() }
                }
            }
        }
        // A system prompt closing, or coming back from System Settings, may have changed an answer.
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification).filter {
                $0.object is OnboardingPanel
            }
        ) { _ in model.access.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.access.refresh()
        }
    }

    /// A chip for each module, which shows it on the stage, and a line about the chosen one.
    private var modulesDetail: some View {
        let inTabs = model.setup.tabs.contains(model.chosenModule)
        return VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            FlowLayout(spacing: Theme.Metrics.rowSpacing) {
                ForEach(IslandModule.allCases.filter(\.isAvailable)) { module in
                    ChipButton(
                        title: module.title, systemImage: module.systemImage, isSelected: module == model.chosenModule
                    ) { model.choose(module) }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(GuideCopy.moduleLines(model.chosenModule, inTabs: inTabs), id: \.self) { line in
                    Text(line)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The keys a step names, then its practice line.
    private var practiceDetail: some View {
        let setup = model.setup
        let id = model.step.id
        return VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            if GuideCopy.showsShortcutCaps(id, setup: setup), let combo = setup.openShortcut {
                KeyCaps(combo: combo)
            } else if !GuideCopy.keyCaps(id, setup: setup).isEmpty {
                HStack(spacing: Theme.Metrics.rowSpacing / 2) {
                    ForEach(GuideCopy.keyCaps(id, setup: setup), id: \.self) { KeyCap($0) }
                }
            }
            if let goal = model.practice {
                PracticeLine(prompt: GuideCopy.prompt(goal, setup: setup), isMet: model.isPracticeMet)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            Spacer()
            if !model.flow.isFirst {
                ChipButton(title: "Back") { withAnimation(Theme.Motion.resize) { model.back() } }
            }
            if model.flow.isLast {
                ChipButton(title: "Open Settings") { model.openSettings() }
                    .disabled(!model.canFinish)
            }
            if model.isAskingPermission {
                // The prompt appears only when this is pressed.
                ChipButton(title: "Grant Permission", isProminent: true) { Task { await model.grant() } }
                    .disabled(model.access.asking != nil)
                    .keyboardShortcut(.defaultAction)
            } else if model.isDeniedPermission, let kind = model.accessKind {
                // macOS won't ask again: turn it on in System Settings, then read it again (coming back to the app does too).
                ChipButton(title: "Check Again") { model.checkAgain() }
                ChipButton(
                    title: "Open System Settings", accessibilityLabel: "Open \(kind.title) in System Settings",
                    isProminent: true
                ) {
                    if let url = model.offItem?.settingsURL ?? kind.settingsURL { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut(.defaultAction)
            } else {
                ChipButton(title: model.primaryTitle, isProminent: true) {
                    withAnimation(Theme.Motion.resize) { model.advance() }
                }
                .disabled(model.flow.isLast && !model.canFinish)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func announce() {
        AccessibilityNotification.Announcement(
            "\(model.title). Step \(model.flow.index + 1) of \(model.flow.count)."
        ).post()
    }
}

/// A permission's glyph and name, and how it stands: a green check beside its glyph when allowed, red when off, and nothing but the
/// name while it is waiting for an answer.
private struct PermissionStatus: View {
    let kind: AccessKind
    let state: PrivacyAccess.State
    let isAsking: Bool

    var body: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            Glyph(systemName: kind.symbol)
            Text(kind.title)
                .font(Theme.Typography.bodyEmphasized)
                .foregroundStyle(Theme.Palette.primary)
            Spacer(minLength: Theme.Metrics.rowSpacing)
            trailing
        }
        .frame(height: Theme.Metrics.hitTarget)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .notAsked:
            Text(isAsking ? "Waiting for macOS\u{2026}" : "Not asked yet")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondary)
        case .allowed:
            HStack(spacing: 4) {
                Glyph(systemName: "checkmark.circle.fill", tint: Theme.Tint.positive)
                Text("Allowed")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        case .denied:
            HStack(spacing: 4) {
                Glyph(systemName: "exclamationmark.circle.fill", tint: Theme.Tint.attention)
                Text("Off")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
    }
}

/// "Try it: ..." until the island in the window does it, then a green check. Green means done, and sits beside its glyph. A practice
/// check never blocks Continue and never advances on its own.
private struct PracticeLine: View {
    let prompt: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            if isMet {
                Glyph(systemName: "checkmark.circle.fill", tint: Theme.Tint.positive)
                Text("Done")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondary)
            } else {
                // A glyph, so the tertiary ink is allowed.
                Image(systemName: "hand.point.up.left")
                    .font(Theme.Typography.glyph)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .frame(width: Theme.Metrics.glyphSlot, height: Theme.Metrics.glyphSlot)
                    .accessibilityHidden(true)
                Text(prompt)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .id(isMet)
        .transition(Theme.Motion.content)
        .animation(Theme.Motion.resize, value: isMet)
        .accessibilityElement(children: .combine)
    }
}

/// The guide as the window shows it: on floating glass, arriving from the notch with the `float` motion.
struct OnboardingRoot: View {
    let model: OnboardingModel

    @State private var arrived = false

    var body: some View {
        OnboardingView(model: model)
            .floatingGlass()
            // The window has a clear background, and macOS passes clicks through clear pixels: the glass may count as clear, which
            // left the ⊗ clickable only on its thin stroke and the rest of the window deaf (found by hand). This fills the glass's shape
            // with something too faint to see, so every point of the window gets its clicks. The panel drags it (`OnboardingPanel`).
            .background(
                Theme.Palette.hitSurface,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.floatRadius, style: .continuous)
            )
            .environment(\.islandSurface, .glass)
            // Scale and fade in; opacity only under Reduce Motion. A modifier, not a transition, so the window can be sized
            // from the view's fitting size before it has arrived.
            .scaleEffect(arrived || Theme.Motion.reduceMotion ? 1 : 0.94, anchor: .top)
            .opacity(arrived ? 1 : 0)
            .onAppear { withAnimation(Theme.Motion.float) { arrived = true } }
    }
}

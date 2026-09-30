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
            IconButton(systemName: "xmark", label: "Close Guide", size: 12) { model.close() }
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
        case .access:
            accessDetail
        case .finish:
            ChipButton(
                title: "Open at Login", systemImage: "power", isSelected: model.launchAtLogin
            ) { model.toggleLaunchAtLogin() }
            // Login Items can be changed in System Settings while the guide is open.
            .onAppear { model.refreshLaunchAtLogin() }
        default:
            EmptyView()
        }
    }

    /// One row for each permission the guide asks for, and a note on the rest.
    private var accessDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AccessKind.allCases, id: \.self) { kind in
                AccessRow(
                    kind: kind, state: model.access.state(of: kind), isAsking: model.access.asking == kind
                ) {
                    Task { await model.access.allow(kind) }
                }
                .frame(height: Theme.Metrics.guideRowHeight, alignment: .top)
            }
            Text(
                "Camera, Microphone, Screen Recording, and Accessibility are asked for the first time you use Mirror, Voice Note, Record Screen, or Clean Keys."
            )
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
            // TEMPORARY (onboarding Skip): remove before release, with OnboardingModel.showsSkip.
            if OnboardingModel.showsSkip, !model.flow.isLast {
                ChipButton(title: "Skip") { Task { await model.skip() } }
            }
            Spacer()
            if !model.flow.isFirst {
                ChipButton(title: "Back") { withAnimation(Theme.Motion.resize) { model.back() } }
            }
            if model.flow.isLast {
                ChipButton(title: "Open Settings") { model.openSettings() }
            }
            ChipButton(title: model.primaryTitle, isProminent: true) {
                withAnimation(Theme.Motion.resize) { model.advance() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func announce() {
        AccessibilityNotification.Announcement(
            "\(model.title). Step \(model.flow.index + 1) of \(model.flow.count)."
        ).post()
    }
}

/// One permission: what it gives, and its state. `notAsked` offers Allow; `allowed` and `denied` say so (a denied permission can't
/// be asked again, so it offers System Settings instead).
private struct AccessRow: View {
    let kind: AccessKind
    let state: PrivacyAccess.State
    let isAsking: Bool
    let allow: () -> Void

    var body: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            Glyph(systemName: kind.symbol)
            VStack(alignment: .leading, spacing: 0) {
                Text(kind.title)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                Text(kind.reason)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            Spacer(minLength: Theme.Metrics.rowSpacing)
            trailing
        }
        .frame(height: Theme.Metrics.hitTarget)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .notAsked:
            ChipButton(title: "Allow", accessibilityLabel: "Allow \(kind.title)", action: allow)
                .disabled(isAsking)
                .opacity(isAsking ? 0.5 : 1)
        case .allowed:
            HStack(spacing: 4) {
                Glyph(systemName: "checkmark.circle.fill", tint: Theme.Tint.positive)
                Text("Allowed")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            .accessibilityElement(children: .combine)
        case .denied:
            HStack(spacing: Theme.Metrics.rowSpacing) {
                Glyph(systemName: "exclamationmark.circle.fill", tint: Theme.Tint.attention)
                ChipButton(title: "Open Settings", accessibilityLabel: "Open \(kind.title) in System Settings") {
                    if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
                }
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
            // Dragging anywhere that isn't a control moves the window. The panel's `isMovableByWindowBackground` alone did not
            // move it (found by hand), so the drag is SwiftUI's. It is a layer behind everything, not a gesture on everything, so
            // a control in front of it is always hit first and its click never has to compete with the drag.
            .background {
                Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.floatRadius, style: .continuous))
                    .gesture(WindowDragGesture())
            }
            .environment(\.islandSurface, .glass)
            // Scale and fade in; opacity only under Reduce Motion. A modifier, not a transition, so the window can be sized
            // from the view's fitting size before it has arrived.
            .scaleEffect(arrived || Theme.Motion.reduceMotion ? 1 : 0.94, anchor: .top)
            .opacity(arrived ? 1 : 0)
            .onAppear { withAnimation(Theme.Motion.float) { arrived = true } }
    }
}

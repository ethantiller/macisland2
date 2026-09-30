import SwiftUI

/// The first-run guide's content: a header, the stage (the real island, drawn from sample data), the step's words, its detail,
/// and the footer. No native controls: every button is `ChipButton` or `IconButton`. Drawn on floating glass by
/// `OnboardingRoot`, so ink is `Theme.Palette` with `\.islandSurface = .glass`.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    /// The live island, which the practice checks watch.
    let island: IslandViewModel
    /// The live island folded back in: the guide can take the keyboard back from it.
    var onFolded: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            header
            stage
            words
            footer
        }
        .frame(width: Theme.Metrics.guideWidth - 2 * Theme.Metrics.floatPadding)
        .onChange(of: model.step.id) { announce() }
        // The practice checks watch the real island. No timers: each change is reported as it happens.
        .onChange(of: island.state) { _, state in
            observeIsland()
            if state == .compact { onFolded() }
        }
        .onChange(of: island.selectedTab) { observeIsland() }
        .onChange(of: island.isFileDragActive) { observeIsland() }
    }

    private func observeIsland() {
        model.observe(
            PracticeGoal.Island(
                state: island.state, tab: island.selectedTab, isFileDragActive: island.isFileDragActive))
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stageLabel)
    }

    private var stageLabel: String {
        let context = model.preview.context
        switch context.presentation {
        case .menuBar: return "The menu bar, with a module\u{2019}s window open."
        case .expanded: return "The island, open on \(context.tab.title)."
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
        case .finish:
            ChipButton(
                title: "Open at Login", systemImage: "power", isSelected: model.launchAtLogin
            ) { model.toggleLaunchAtLogin() }
        default:
            EmptyView()
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

/// "Try it: ..." until the real island does it, then a green check. Green means done, and sits beside its glyph. A practice
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
    let island: IslandViewModel
    var onFolded: () -> Void = {}

    @State private var arrived = false

    var body: some View {
        OnboardingView(model: model, island: island, onFolded: onFolded)
            .floatingGlass()
            .environment(\.islandSurface, .glass)
            // Scale and fade in; opacity only under Reduce Motion. A modifier, not a transition, so the window can be sized
            // from the view's fitting size before it has arrived.
            .scaleEffect(arrived || Theme.Motion.reduceMotion ? 1 : 0.94, anchor: .top)
            .opacity(arrived ? 1 : 0)
            .onAppear { withAnimation(Theme.Motion.float) { arrived = true } }
    }
}

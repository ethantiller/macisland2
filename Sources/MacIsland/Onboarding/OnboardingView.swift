import SwiftUI

/// The first-run guide's content: a header, the stage (the real island, drawn from sample data), the step's words, its detail,
/// and the footer. No native controls: every button is `ChipButton` or `IconButton`. Drawn on floating glass by
/// `OnboardingRoot`, so ink is `Theme.Palette` with `\.islandSurface = .glass`.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    /// The live island, which the practice checks watch.
    let island: IslandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            header
            stage
            words
            footer
        }
        .frame(width: Theme.Metrics.guideWidth - 2 * Theme.Metrics.floatPadding)
        .onChange(of: model.step.id) { announce() }
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
        case .finish:
            ChipButton(
                title: "Open at Login", systemImage: "power", isSelected: model.launchAtLogin
            ) { model.toggleLaunchAtLogin() }
        default:
            EmptyView()
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

/// The guide as the window shows it: on floating glass, arriving from the notch with the `float` motion.
struct OnboardingRoot: View {
    let model: OnboardingModel
    let island: IslandViewModel

    @State private var arrived = false

    var body: some View {
        OnboardingView(model: model, island: island)
            .floatingGlass()
            .environment(\.islandSurface, .glass)
            // Scale and fade in; opacity only under Reduce Motion. A modifier, not a transition, so the window can be sized
            // from the view's fitting size before it has arrived.
            .scaleEffect(arrived || Theme.Motion.reduceMotion ? 1 : 0.94, anchor: .top)
            .opacity(arrived ? 1 : 0)
            .onAppear { withAnimation(Theme.Motion.float) { arrived = true } }
    }
}

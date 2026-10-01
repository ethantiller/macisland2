import AppKit
import SwiftUI
import Testing

@testable import MacIsland

/// Renders the first-run guide and the Settings tour for design review. Opt-in, like `IslandSnapshots`:
/// `ISLAND_SNAPSHOT_DIR=/some/dir ./scripts/test.sh --filter OnboardingSnapshots`.
///
/// `ImageRenderer` can't draw Liquid Glass, so the guide's content is drawn with `\.islandSurface = .glass` on a flat window color,
/// once in light and once in dark. What it can't show (the glass, the window's place, the ring over real Form rows, focus) is
/// checked by hand.
@MainActor
struct OnboardingSnapshots {
    private let outputDirectory = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"].map(
        URL.init(fileURLWithPath:))
    private static let enabled = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil

    // MARK: Drawing

    private func png<V: View>(_ view: V, _ name: String) {
        guard let outputDirectory else { return }
        let renderer = ImageRenderer(content: view.environment(\.isSnapshot, true))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try? data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    private func window(dark: Bool) -> Color { dark ? Color(white: 0.16) : Color(white: 0.93) }

    /// Content on glass ink over a flat window color, in light or dark.
    private func onGlass<V: View>(_ view: V, dark: Bool, padding: CGFloat = Theme.Metrics.floatPadding) -> some View {
        view
            .padding(padding)
            .environment(\.islandSurface, .glass)
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(window(dark: dark))
    }

    // MARK: The guide

    private struct Guide {
        let model: OnboardingModel
        let island: IslandViewModel
    }

    private func makeGuide(access: StubAccess? = nil) -> Guide {
        let access = access ?? StubAccess()
        let island = TestSupport.makeViewModel()
        let suite = "MacIslandSnapshots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = OnboardingState(defaults: defaults, isExistingInstall: { false })
        let preview = IslandPreviewModel(live: island.features)
        preview.viewModel.geometry = island.geometry
        preview.allowsMenuBar = true
        let model = OnboardingModel(
            state: state, settings: island.settings, geometry: { island.geometry }, preview: preview,
            access: AccessModel(provider: access, settings: island.settings, onBluetoothAllowed: {}),
            replay: false, openSettings: {}, onEnd: { _ in })
        return Guide(model: model, island: island)
    }

    private func renderGuide(_ guide: Guide, _ name: String) {
        for dark in [false, true] {
            png(
                onGlass(OnboardingView(model: guide.model), dark: dark),
                dark ? "\(name)-dark" : name)
        }
    }

    @Test(.enabled(if: OnboardingSnapshots.enabled))
    func renderEveryStep() async throws {
        let guide = makeGuide()
        defer { guide.model.stop() }
        try await Task.sleep(for: .milliseconds(150))
        for index in 0..<guide.model.flow.count {
            let number = String(format: "%02d", index + 1)
            renderGuide(guide, "40-guide-\(number)-\(guide.model.step.id.rawValue)")
            guide.model.next(animated: false)
        }
    }

    @Test(.enabled(if: OnboardingSnapshots.enabled))
    func renderAMetPracticeLine() async throws {
        let guide = makeGuide()
        defer { guide.model.stop() }
        try await Task.sleep(for: .milliseconds(150))
        guide.model.next(animated: false)
        guide.model.observe(PracticeGoal.Island(state: .peek, tab: .home, isFileDragActive: false))
        renderGuide(guide, "40-guide-02-peek-done")
    }

    @Test(.enabled(if: OnboardingSnapshots.enabled))
    func renderTheAccessStepMixed() async throws {
        // Calendars is allowed, so its step is left out; the rest show Grant Permission, or Open System Settings and Check Again.
        let guide = makeGuide(
            access: StubAccess(states: [.calendars: .allowed, .reminders: .denied, .screenRecording: .denied]))
        defer { guide.model.stop() }
        try await Task.sleep(for: .milliseconds(150))
        while guide.model.step.id != .reminders { guide.model.next(animated: false) }
        renderGuide(guide, "40-guide-09-access-denied")
        while guide.model.step.id != .screenRecording { guide.model.next(animated: false) }
        renderGuide(guide, "40-guide-09-access-screen-denied")
        while guide.model.step.id != .bluetooth { guide.model.back(animated: false) }
        renderGuide(guide, "40-guide-09-access-not-asked")
    }

    @Test(.enabled(if: OnboardingSnapshots.enabled))
    func renderTheLastStepWithWhatIsStillNeeded() async throws {
        let guide = makeGuide(access: StubAccess(states: [.calendars: .allowed, .focus: .denied]))
        defer { guide.model.stop() }
        try await Task.sleep(for: .milliseconds(150))
        guide.model.go(to: .finish, animated: false)
        renderGuide(guide, "40-guide-19-finish-needed")
    }

    // MARK: The tour

    /// A target (a button), its ring, and the callout placed beside it, in a window-sized canvas.
    private func tourScene(_ stop: TourStop, index: Int, placement: TourStop.Placement, dark: Bool) -> some View {
        let canvas = CGSize(width: 800, height: 360)
        let target = CGRect(x: 340, y: 150, width: 120, height: 28)
        let callout = TourCallout(
            stop: stop, index: index, count: TourStop.all.count, onBack: {}, onNext: {}, onEnd: {})
        let size = NSHostingView(rootView: callout).fittingSize
        let placed = CalloutPlacement.place(
            target: target, size: size, in: CGRect(origin: .zero, size: canvas), preferred: placement,
            gap: Theme.Metrics.tourRingInset + Theme.Metrics.tourGap, arrow: Theme.Metrics.tourArrow,
            edgeInset: Theme.Metrics.tourEdgeInset, cornerRadius: Theme.Metrics.cardRadius)
        return ZStack(alignment: .topLeading) {
            FieldButton(title: "Target", systemImage: "gearshape") {}
                .frame(width: target.width, height: target.height)
                .position(x: target.midX, y: target.midY)
            TourRing(frame: target)
            TourArrowView(placed: placed)
            callout.offset(x: placed.frame.minX, y: placed.frame.minY)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .environment(\.colorScheme, dark ? .dark : .light)
        .background(window(dark: dark))
    }

    @Test(.enabled(if: OnboardingSnapshots.enabled))
    func renderEveryStop() {
        for (index, stop) in TourStop.all.enumerated() {
            let number = String(format: "%02d", index + 1)
            for dark in [false, true] {
                png(
                    tourScene(stop, index: index, placement: stop.placement, dark: dark),
                    "43-tour-\(number)-\(stop.id)" + (dark ? "-dark" : ""))
            }
        }
    }

    @Test(.enabled(if: OnboardingSnapshots.enabled))
    func renderEverySide() {
        let stop = TourStop.all[2]
        for (name, side) in [
            ("above", TourStop.Placement.above), ("below", .below), ("leading", .leading), ("trailing", .trailing),
        ] {
            png(tourScene(stop, index: 2, placement: side, dark: false), "42-tour-placement-\(name)")
        }
    }

    // MARK: Components

    @Test(.enabled(if: OnboardingSnapshots.enabled))
    func renderStepDots() {
        func rows() -> some View {
            VStack(alignment: .leading, spacing: 12) {
                StepDots(count: 10, current: 0)
                StepDots(count: 10, current: 4)
                StepDots(count: 10, current: 9)
            }
        }
        png(rows().padding(16).background(Color.black), "44-step-dots")
        png(onGlass(rows(), dark: false, padding: 16), "44-step-dots-glass")
    }

    @Test(.enabled(if: OnboardingSnapshots.enabled))
    func renderKeyCaps() {
        func rows() -> some View {
            VStack(alignment: .leading, spacing: 12) {
                KeyCaps(combo: .openDefault)
                HStack(spacing: 4) {
                    KeyCap("\u{2190}")
                    KeyCap("\u{2192}")
                    KeyCap("Esc")
                }
            }
        }
        png(rows().padding(16).background(Color.black), "44-key-caps")
        png(onGlass(rows(), dark: false, padding: 16), "44-key-caps-glass")
    }
}

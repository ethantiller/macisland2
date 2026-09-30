import AVFoundation
import AppKit
import Foundation
import Testing

@testable import MacIsland

@MainActor
struct CameraMirrorTests {
    @Test func startsThenReleasesTheCamera() async {
        let camera = StubCamera()
        let mirror = CameraMirror(provider: camera)
        await mirror.toggle()
        #expect(mirror.isOn && mirror.session != nil && camera.starts == 1)
        await mirror.toggle()
        #expect(!mirror.isOn && mirror.session == nil && camera.stops == 1)
    }

    @Test func aDeniedCameraStaysOffAndSaysSo() async {
        let camera = StubCamera()
        camera.access = .denied
        let mirror = CameraMirror(provider: camera)
        await mirror.toggle()
        #expect(mirror.isOn && mirror.access == .denied && mirror.session == nil && camera.starts == 0)
        mirror.stop()
        #expect(!mirror.isOn)
    }

    @Test func askingFirstAndBeingRefusedIsDenied() async {
        let camera = StubCamera()
        camera.access = .notDetermined
        camera.allowsWhenAsked = false
        let mirror = CameraMirror(provider: camera)
        await mirror.toggle()
        #expect(mirror.access == .denied && camera.starts == 0)

        let allowed = StubCamera()
        allowed.access = .notDetermined
        let other = CameraMirror(provider: allowed)
        await other.toggle()
        #expect(other.access == .granted && other.session != nil)
    }

    @Test func noCameraIsReported() async {
        let camera = StubCamera()
        camera.failsToStart = true
        let mirror = CameraMirror(provider: camera)
        await mirror.toggle()
        #expect(mirror.isUnavailable && mirror.session == nil)
    }

    @Test func foldingTheIslandOrChangingTabReleasesIt() async {
        let camera = StubCamera()
        let viewModel = TestSupport.makeViewModel(camera: camera)
        viewModel.startMirror()
        for _ in 0..<50 where viewModel.mirror.session == nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(viewModel.mirror.isOn && viewModel.selectedTab == .tools && viewModel.state == .expanded)
        viewModel.state = .compact
        #expect(!viewModel.mirror.isOn && camera.stops >= 1)

        viewModel.startMirror()
        for _ in 0..<50 where viewModel.mirror.session == nil { try? await Task.sleep(for: .milliseconds(10)) }
        viewModel.select(.notes)
        #expect(!viewModel.mirror.isOn)
    }

    @Test func doneReleasesItToo() async {
        let viewModel = TestSupport.makeViewModel()
        viewModel.startMirror()
        for _ in 0..<50 where viewModel.mirror.session == nil { try? await Task.sleep(for: .milliseconds(10)) }
        viewModel.stopMirror()
        #expect(!viewModel.mirror.isOn && !viewModel.isPinnedOpen)
    }

    @Test func theMirrorReplacesTheToolsAndFitsThePanel() async {
        let viewModel = TestSupport.makeViewModel()
        viewModel.selectedTab = .tools
        viewModel.state = .expanded
        let toolsHeight = viewModel.contentHeight(for: .tools)
        viewModel.startMirror()
        for _ in 0..<50 where !viewModel.mirror.isOn { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(viewModel.contentHeight(for: .tools) == Theme.Metrics.mirrorHeight)
        #expect(viewModel.contentHeight(for: .tools) > toolsHeight)
        #expect(viewModel.size.height <= ScreenGeometry.panelSize.height)
        #expect(Theme.Metrics.mirrorWidth / Theme.Metrics.mirrorHeight > 1.7)
    }
}

@MainActor
struct TwoActionBannerTests {
    private func banner(_ log: Log) -> IslandBanner {
        IslandBanner(
            systemImage: "calendar", tint: Theme.Tint.neutral, title: "Standup", detail: "In 5 minutes",
            actions: [
                .init(title: "Join") { log.lines.append("join") },
                .init(title: "Check Camera") { log.lines.append("camera") },
            ]
        )
    }

    final class Log { var lines: [String] = [] }

    @Test func eachActionRunsAndTheBannerGoes() {
        let log = Log()
        let viewModel = TestSupport.makeViewModel()
        viewModel.showBanner(banner(log))
        viewModel.performBannerAction(at: 1)
        #expect(log.lines == ["camera"] && viewModel.banner == nil)
        viewModel.showBanner(banner(log))
        viewModel.performBannerAction()
        #expect(log.lines == ["camera", "join"])
    }

    @Test func anIndexThatIsNotThereDoesNothing() {
        let log = Log()
        let viewModel = TestSupport.makeViewModel()
        viewModel.showBanner(banner(log))
        viewModel.performBannerAction(at: 5)
        #expect(log.lines.isEmpty)
    }

    @Test func aMeetingWithALinkOffersJoinThenCheckCamera() {
        let agenda = AgendaMonitor()
        var checked = 0
        let item = AgendaItem(
            id: "a", kind: .event, title: "Standup", date: Date().addingTimeInterval(300),
            joinURL: URL(string: "https://zoom.us/j/1"))
        let banner = AgendaAction.announcement(for: item, agenda: agenda) { checked += 1 }
        #expect(banner.actions.map(\.title) == ["Join", "Check Camera"])
        banner.actions[1].perform()
        #expect(checked == 1)

        let lunch = AgendaItem(
            id: "b", kind: .event, title: "Lunch", date: Date().addingTimeInterval(300), joinURL: nil)
        #expect(AgendaAction.announcement(for: lunch, agenda: agenda) {}.actions.isEmpty)
        let reminder = AgendaItem(id: "c", kind: .reminder, title: "Call", date: Date(), joinURL: nil)
        #expect(AgendaAction.announcement(for: reminder, agenda: agenda) {}.actions.map(\.title) == ["Done"])
    }
}

@MainActor
struct ScreenRecorderTests {
    private func recorder(
        _ screen: StubScreen, shelf: ShelfModel? = nil, maxDuration: Duration = ScreenRecorder.maxDuration
    ) -> ScreenRecorder {
        ScreenRecorder(recorder: screen, shelf: shelf ?? ShelfModel(), maxDuration: maxDuration)
    }

    @Test func recordsARegionThenPutsTheMovieOnTheShelf() async {
        let screen = StubScreen()
        let shelf = ShelfModel()
        let recorder = recorder(screen, shelf: shelf)
        var finished: URL?
        recorder.onFinish = { finished = $0 }
        let region = CGRect(x: 10, y: 20, width: 300, height: 200)
        await recorder.start(region: region)
        #expect(recorder.isRecording && screen.regions == [region])
        await recorder.stop()
        #expect(!recorder.isRecording && finished == screen.movie && shelf.items.contains(screen.movie))
    }

    @Test func aWholeDisplayHasNoRegion() async {
        let screen = StubScreen()
        let recorder = recorder(screen)
        await recorder.start(region: nil)
        #expect(screen.regions.count == 1 && screen.regions[0] == nil)
        await recorder.stop()
    }

    @Test func withoutAccessItAsksForSettings() async {
        let screen = StubScreen()
        screen.hasAccess = false
        let recorder = recorder(screen)
        var needsAccess = 0
        recorder.onNeedsAccess = { needsAccess += 1 }
        await recorder.start(region: nil)
        #expect(needsAccess == 1 && !recorder.isRecording && screen.regions.isEmpty)

        // Allowed at the prompt: it goes ahead.
        screen.allowsWhenAsked = true
        await recorder.start(region: nil)
        #expect(recorder.isRecording)
        await recorder.stop()
    }

    @Test func aFailureToStartIsReported() async {
        let screen = StubScreen()
        screen.failsToStart = true
        let recorder = recorder(screen)
        var reason: String?
        recorder.onFail = { reason = $0 }
        await recorder.start(region: nil)
        #expect(!recorder.isRecording && reason == "No display was found.")
    }

    @Test func stopsOnItsOwnAtTheCap() async {
        let screen = StubScreen()
        let shelf = ShelfModel()
        let recorder = recorder(screen, shelf: shelf, maxDuration: .milliseconds(40))
        await recorder.start(region: nil)
        for _ in 0..<100 where recorder.isRecording { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(!recorder.isRecording && screen.stops == 1 && shelf.items.contains(screen.movie))
        #expect(ScreenRecorder.maxDuration == .seconds(1800))
    }

    @Test func aSecondStartWhileRecordingIsIgnored() async {
        let screen = StubScreen()
        let recorder = recorder(screen)
        await recorder.start(region: nil)
        await recorder.start(region: nil)
        #expect(screen.regions.count == 1)
        await recorder.stop()
        await recorder.stop()
        #expect(screen.stops == 1)
    }

    @Test func theMovieIsNamedForTheTimeAndNeverOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ScreenRecorder.destination(at: date, in: folder)
        #expect(first.lastPathComponent.hasPrefix("Screen Recording ") && first.pathExtension == "mov")
        try Data().write(to: first)
        #expect(ScreenRecorder.destination(at: date, in: folder) != first)
    }

    @Test func theToolTogglesRecordingAndTheIslandFoldsToChoose() async {
        let screen = StubScreen()
        let viewModel = TestSupport.makeViewModel(screen: screen)
        var picks: [RegionSelection] = [.region(CGRect(x: 1, y: 2, width: 3, height: 4)), .display, .cancelled]
        var offered = 0
        viewModel.pickRegion = { completion in
            offered += 1
            completion(picks.removeFirst())
        }
        viewModel.state = .expanded
        viewModel.toggleScreenRecording()
        #expect(viewModel.state == .compact && offered == 1)
        for _ in 0..<50 where !viewModel.screenRecorder.isRecording { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(screen.regions == [CGRect(x: 1, y: 2, width: 3, height: 4)])

        // While recording, the tool stops it instead of asking again.
        viewModel.toggleScreenRecording()
        for _ in 0..<50 where viewModel.screenRecorder.isRecording { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(offered == 1 && screen.stops == 1)

        viewModel.toggleScreenRecording()
        for _ in 0..<50 where !viewModel.screenRecorder.isRecording { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(screen.regions.count == 2 && screen.regions[1] == nil)
        viewModel.stopScreenRecording()
        for _ in 0..<50 where viewModel.screenRecorder.isRecording { try? await Task.sleep(for: .milliseconds(10)) }

        viewModel.toggleScreenRecording()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!viewModel.screenRecorder.isRecording && screen.regions.count == 2)
    }

    @Test func aClickIsTheWholeDisplayAndADragIsARegionFromTheTop() {
        let start = CGPoint(x: 100, y: 100)
        #expect(RegionPicker.selection(from: start, to: CGPoint(x: 102, y: 101), screenHeight: 900) == .display)
        // Dragged up and to the left, on a 900 pt tall screen: the y flips to count from the top.
        #expect(
            RegionPicker.selection(from: CGPoint(x: 300, y: 400), to: CGPoint(x: 100, y: 200), screenHeight: 900)
                == .region(CGRect(x: 100, y: 500, width: 200, height: 200)))
        #expect(
            RegionPicker.rect(from: CGPoint(x: 5, y: 9), to: CGPoint(x: 1, y: 3))
                == CGRect(x: 1, y: 3, width: 4, height: 6))
    }
}

@MainActor
struct VoiceRecorderTests {
    private func makeRecorder(
        _ transcriber: StubTranscriber, maxDuration: Duration = VoiceRecorder.maxDuration
    ) -> (VoiceRecorder, NotesModel, ShelfModel) {
        let notes = NotesModel(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let shelf = ShelfModel()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (
            VoiceRecorder(
                transcriber: transcriber, notes: notes, shelf: shelf, folder: folder, maxDuration: maxDuration), notes,
            shelf
        )
    }

    @Test func stoppingMakesANoteOfTheWordsAndShelvesTheAudio() async throws {
        let transcriber = StubTranscriber()
        let (voice, notes, shelf) = makeRecorder(transcriber)
        var saved = 0
        voice.onSaved = { saved += 1 }
        await voice.start()
        #expect(voice.isRecording && voice.level == 0.4)
        let audio = try #require(transcriber.file)
        #expect(audio.pathExtension == "m4a" && audio.lastPathComponent.hasPrefix("Voice Note "))
        await voice.stop()

        #expect(!voice.isRecording && saved == 1)
        let note = try #require(notes.notes.first)
        #expect(note.title.hasPrefix("Voice Note, "))
        #expect(note.body.hasSuffix("\n\nBuy milk and call the bank."))
        #expect(shelf.items.contains(audio))
    }

    @Test func silenceStillMakesANote() async throws {
        let transcriber = StubTranscriber()
        transcriber.transcript = "  \n "
        let (voice, notes, _) = makeRecorder(transcriber)
        await voice.start()
        await voice.stop()
        #expect(try #require(notes.notes.first).body.hasSuffix("No speech was recognized."))
    }

    @Test func aFailureToStartIsReportedAndNothingRecords() async {
        let transcriber = StubTranscriber()
        transcriber.failsToStart = true
        let (voice, notes, _) = makeRecorder(transcriber)
        var error: Error?
        voice.onFail = { error = $0 }
        await voice.start()
        #expect(!voice.isRecording && (error as? VoiceError) == .microphoneDenied && notes.notes.isEmpty)
    }

    @Test func stopsOnItsOwnAtTheCap() async {
        let transcriber = StubTranscriber()
        let (voice, notes, _) = makeRecorder(transcriber, maxDuration: .milliseconds(40))
        await voice.start()
        for _ in 0..<100 where voice.isRecording { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(!voice.isRecording && transcriber.stops == 1 && notes.notes.count == 1)
        #expect(VoiceRecorder.maxDuration == .seconds(600))
    }

    @Test func aMutedMicrophoneOffersToUnmuteFirstAndDoesNotRecord() async {
        let transcriber = StubTranscriber()
        let viewModel = TestSupport.makeViewModel(transcriber: transcriber)
        viewModel.micMute.isMuted = true
        viewModel.toggleVoiceNote()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.banner?.title == "Mic Is Muted" && viewModel.banner?.actions.map(\.title) == ["Unmute"])
        #expect(!viewModel.voice.isRecording && transcriber.file == nil)
    }

    @Test func anOpenMicrophoneStartsAndStopsTheNote() async {
        let transcriber = StubTranscriber()
        let viewModel = TestSupport.makeViewModel(transcriber: transcriber)
        viewModel.micMute.isMuted = false
        viewModel.toggleVoiceNote()
        for _ in 0..<50 where !viewModel.voice.isRecording { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(viewModel.voice.isRecording)
        viewModel.toggleVoiceNote()
        for _ in 0..<50 where viewModel.voice.isRecording { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(transcriber.stops == 1 && viewModel.notes.notes.count == 1)
    }

    @Test func theTitleIsTheTime() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(VoiceRecorder.title(for: date) == "Voice Note, " + date.formatted(date: .omitted, time: .shortened))
    }

    @Test func theLevelMeterReadsLoudness() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100))
        buffer.frameLength = 100
        let meter = LevelMeter()
        meter.update(from: buffer)
        #expect(meter.value == 0)
        for index in 0..<100 { buffer.floatChannelData![0][index] = 0.5 }
        meter.update(from: buffer)
        #expect(meter.value > 0.9 && meter.value <= 1)
        meter.reset()
        #expect(meter.value == 0)
    }
}

@MainActor
struct RecordingActivityTests {
    private func startVoice(_ viewModel: IslandViewModel) async {
        await viewModel.voice.start()
    }

    @Test func recordingOutranksTheClocksAndYieldsToAlertsAndBanners() async {
        let viewModel = TestSupport.makeViewModel()
        viewModel.timer.start(minutes: 5)
        viewModel.work.begin("Zipping")
        await startVoice(viewModel)
        #expect(viewModel.compactActivities == [.recording(.voice), .timer, .working("Zipping")])

        viewModel.flash(IslandAlert(systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "80%"))
        #expect(
            viewModel.compactActivities.first == .alert(viewModel.alert!)
                && viewModel.compactActivities[1] == .recording(.voice))

        viewModel.showBanner(IslandBanner(systemImage: "bell", tint: Theme.Tint.neutral, title: "Hi"))
        #expect(viewModel.compactActivities.count == 1)
        if case .banner = viewModel.compactActivity {} else { Issue.record("a banner leads") }
    }

    @Test func aVoiceNoteHasAPeekAndAScreenRecordingIsAStopButton() async {
        let screen = StubScreen()
        let viewModel = TestSupport.makeViewModel(screen: screen)
        await viewModel.voice.start()
        #expect(viewModel.peekContentHeight == Theme.Metrics.glanceHeight)
        #expect(viewModel.compactControlRect == nil)
        await viewModel.voice.stop()

        await viewModel.screenRecorder.start(region: nil)
        #expect(viewModel.compactActivity == .recording(.screen))
        #expect(viewModel.compactControlRect == viewModel.hitRect)
        viewModel.tapCompact()
        for _ in 0..<50 where viewModel.screenRecorder.isRecording { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(!viewModel.screenRecorder.isRecording && screen.stops == 1 && viewModel.state == .compact)
    }

    @Test func tappingCompactOtherwiseOpens() {
        let viewModel = TestSupport.makeViewModel()
        viewModel.tapCompact()
        #expect(viewModel.state == .expanded)
    }
}

@MainActor
struct CaptureToolTests {
    @Test func theToolsAreThereAndFillTheGrid() {
        let catalog = ToolCatalog(viewModel: TestSupport.makeViewModel())
        let mirror = catalog.item(for: .mirror)
        #expect(mirror.title == "Mirror" && mirror.systemImage == "person.crop.rectangle")
        let record = catalog.item(for: .recordScreen)
        #expect(record.title == "Record" && record.label == "Record Screen" && record.systemImage == "record.circle")
        #expect(ToolID.allCases.count == 9 && ToolID.allCases.count + 1 <= 2 * 6)
    }

    @Test func theMirrorToolTurnsOn() async {
        let viewModel = TestSupport.makeViewModel()
        let tool = ToolCatalog(viewModel: viewModel).item(for: .mirror)
        #expect(!tool.isOn)
        tool.action()
        for _ in 0..<50 where !viewModel.mirror.isOn { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(ToolCatalog(viewModel: viewModel).item(for: .mirror).isOn)
        viewModel.stopMirror()
    }
}

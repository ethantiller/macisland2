import AppKit
import Foundation
import Testing

@testable import MacIsland

@MainActor
struct SettingsPreviewTests {
    private func makeReference() -> (preview: IslandPreviewModel, reference: IslandViewModel) {
        let reference = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: reference.features)
        preview.viewModel.geometry = reference.geometry
        reference.nowPlaying.apply(PreviewSamples.track())
        return (preview, reference)
    }

    @Test func previewSizesMatchTheRealIslandForEveryPresentationAndTab() {
        let (preview, reference) = makeReference()
        defer { preview.stop() }

        preview.show(PreviewContext(presentation: .compact))
        reference.state = .compact
        #expect(preview.viewModel.size == reference.size)

        preview.show(PreviewContext(presentation: .peek))
        reference.state = .peek
        #expect(preview.viewModel.size == reference.size)

        preview.show(PreviewContext(presentation: .banner))
        reference.showBanner(PreviewSamples.banner(), for: .seconds(86_400), respectingFocus: false)
        #expect(preview.viewModel.size == reference.size)
        reference.dismissBanner()

        for tab in IslandModule.allCases where tab.isAvailable {
            preview.show(PreviewContext(presentation: .expanded, tab: tab))
            reference.selectedTab = tab
            reference.state = .expanded
            #expect(preview.viewModel.size == reference.size, "\(tab)")
        }
    }

    @Test func drivingThePreviewNeverTouchesTheRealShelfOrHistory() {
        let (preview, _) = makeReference()
        let marker = "/tmp/macisland-preview-isolation-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: marker, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: marker) }

        preview.viewModel.shelf.add([URL(fileURLWithPath: marker)])
        preview.viewModel.pomodoro.toggle()
        preview.viewModel.pomodoro.advance(completed: true)
        preview.viewModel.pomodoro.reset()
        for presentation in PreviewPresentation.allCases {
            preview.show(PreviewContext(presentation: presentation, tab: .shelf))
        }
        preview.stop()

        let saved = UserDefaults.standard.stringArray(forKey: "shelf.paths") ?? []
        #expect(!saved.contains(marker))
    }

    @Test func thePreviewIsSampleDataThatNeverRuns() {
        let (preview, _) = makeReference()
        defer { preview.stop() }
        let viewModel = preview.viewModel
        #expect(viewModel.nowPlaying.state.hasMedia)
        #expect(viewModel.agenda.next?.title == "Design review")
        #expect(!viewModel.timer.isActive && !viewModel.stopwatch.isActive && !viewModel.pomodoro.isActive)
        #expect(!viewModel.screenRecorder.isRecording && !viewModel.voice.isRecording)
        #expect(!viewModel.mirror.isOn)
    }

    @Test func eachPaneSaysWhatThePreviewShows() {
        #expect(SettingsPane.notifications.previewContext?.presentation == .banner)
        #expect(SettingsPane.tools.previewContext?.tab == .tools)
        #expect(SettingsPane.privacy.previewContext == nil)
    }
}

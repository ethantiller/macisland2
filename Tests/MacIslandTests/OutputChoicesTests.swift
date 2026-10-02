import CoreAudio
import Testing

@testable import MacIsland

@MainActor
struct OutputChoicesTests {
    @Test func otherOutputsExcludeTheCurrentDevice() {
        let current = AudioOutputs.Device(
            id: AudioDeviceID(1), name: "Built-in", transportType: kAudioDeviceTransportTypeBuiltIn, uid: "built-in")
        let alternative = AudioOutputs.Device(
            id: AudioDeviceID(2), name: "Headphones", transportType: kAudioDeviceTransportTypeBluetooth, uid: "headphones")
        let devices = [current, alternative]

        #expect(AudioOutputs.currentDevice(in: devices, defaultDeviceID: current.id) == current)
        #expect(AudioOutputs.otherDevices(in: devices, defaultDeviceID: current.id) == [alternative])
    }

    @Test func outputListHeightCapsRowsAndAccountsForDisconnectedCaption() {
        #expect(
            IslandViewModel.outputListHeight(connectedCount: 8, disconnectedCount: 3)
                == CGFloat(Theme.Metrics.peekOutputMaxRows) * Theme.Metrics.outputRowHeight
                    + Theme.Metrics.outputCaptionHeight)
        #expect(
            IslandViewModel.outputListHeight(connectedCount: 1, disconnectedCount: 1)
                == 2 * Theme.Metrics.outputRowHeight + Theme.Metrics.outputCaptionHeight)
    }

    @Test func previousDefaultTakesTheClickedSatellitesSlot() {
        #expect(OutputSatelliteOrder.replacingSelected(3, with: 1, in: [2, 3, 4]) == [2, 1, 4])
    }

    @Test func peekOutputListAddsCappedHeightAndResetsWhenPeekCloses() {
        let bluetooth = StubBluetooth()
        bluetooth.devices = [PairedDevice(id: "airpods", name: "AirPods Pro", isConnected: false)]
        let viewModel = TestSupport.makeViewModel(bluetooth: bluetooth, outputs: sampleOutputs())
        var state = NowPlayingState()
        state.title = "Track"
        state.artist = "Artist"
        viewModel.nowPlaying.apply(state)
        viewModel.state = .peek

        let closedHeight = viewModel.mediaContentHeight(peek: true)
        viewModel.showsPeekOutputList = true
        #expect(viewModel.mediaContentHeight(peek: true) == Theme.Metrics.playerPeekArtwork
            + 2 * Theme.Metrics.playerSpacing + Theme.Metrics.outputRowHeight + viewModel.mediaOutputListHeight)
        #expect(viewModel.mediaContentHeight(peek: true) > closedHeight)

        viewModel.state = .compact
        #expect(!viewModel.showsPeekOutputList)
    }

    @Test func satelliteHitAreaIncludesTheGapAndExpandsForAHoveredPill() throws {
        let viewModel = TestSupport.makeViewModel(outputs: sampleOutputs())
        viewModel.selectedTab = .media
        viewModel.state = .expanded
        viewModel.showsMediaOutputs = true

        let circles = try #require(viewModel.outputSatellitesRect)
        #expect(circles.width == Theme.Metrics.outputSatelliteGap + Theme.Metrics.outputSatelliteSize)
        #expect(viewModel.isOverIsland(CGPoint(x: circles.minX + 2, y: circles.midY)))
        #expect(viewModel.isOverIsland(CGPoint(x: circles.maxX - 2, y: circles.midY)))

        viewModel.setOutputSatelliteHover("output-2", hovering: true)
        let pill = try #require(viewModel.outputSatellitesRect)
        #expect(pill.width == Theme.Metrics.outputSatelliteGap + Theme.Metrics.outputPillMaxWidth)
        #expect(viewModel.isOverIsland(CGPoint(x: pill.maxX - 2, y: pill.midY)))
    }

    private func sampleOutputs() -> AudioOutputs {
        let devices = [
            AudioOutputs.Device(id: AudioDeviceID(1), name: "MacBook Speakers", transportType: kAudioDeviceTransportTypeBuiltIn, uid: "builtin"),
            AudioOutputs.Device(id: AudioDeviceID(2), name: "Studio Display", transportType: kAudioDeviceTransportTypeDisplayPort, uid: "display"),
            AudioOutputs.Device(id: AudioDeviceID(3), name: "Living Room", transportType: kAudioDeviceTransportTypeAirPlay, uid: "airplay"),
            AudioOutputs.Device(id: AudioDeviceID(4), name: "HDMI", transportType: kAudioDeviceTransportTypeHDMI, uid: "hdmi"),
            AudioOutputs.Device(id: AudioDeviceID(5), name: "USB DAC", transportType: kAudioDeviceTransportTypeUSB, uid: "usb"),
            AudioOutputs.Device(id: AudioDeviceID(6), name: "Office", transportType: kAudioDeviceTransportTypeBluetooth, uid: "office"),
        ]
        return AudioOutputs(devices: devices, defaultDeviceID: devices[0].id)
    }
}
struct OutputPillTests {
    @Test func aPillIsOnlyAsWideAsItsName() {
        let short = OutputPill.width(textWidth: 30)
        let long = OutputPill.width(textWidth: 90)
        #expect(short < long)
        #expect(long < Theme.Metrics.outputPillMaxWidth)
        #expect(short >= Theme.Metrics.outputSatelliteSize)
    }

    @Test func aLongNameStopsAtTheCap() {
        #expect(OutputPill.width(textWidth: 900) == Theme.Metrics.outputPillMaxWidth)
    }

    @Test func aColumnIsItsDotsAndTheSpacesBetween() {
        #expect(OutputPill.columnHeight(count: 0) == 0)
        #expect(OutputPill.columnHeight(count: 3)
            == 3 * Theme.Metrics.outputSatelliteSize + 2 * Theme.Metrics.outputSatelliteSpacing)
    }
}

struct MixerPinningTests {
    private func row(_ id: String) -> MixerRow { MixerRow(id: id, name: id, isPlaying: true, isNeverTapped: false) }

    @Test func thePlayerComesFirstAndNothingIsDropped() {
        let rows = [row("a"), row("b"), row("c")]
        #expect(MixerRow.pinning(rows, first: "c").map(\.id) == ["c", "a", "b"])
    }

    @Test func anUnknownOrMissingPlayerChangesNothing() {
        let rows = [row("a"), row("b")]
        #expect(MixerRow.pinning(rows, first: "z") == rows)
        #expect(MixerRow.pinning(rows, first: nil) == rows)
    }
}

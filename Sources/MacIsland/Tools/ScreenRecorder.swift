import AppKit
import CoreMedia
import Observation
import ScreenCaptureKit

/// The screen, behind a protocol so tests never record one.
@MainActor
protocol ScreenRecording: AnyObject {
    var hasAccess: Bool { get }
    /// Asks the system for Screen Recording access. `false` until the person allows it in Settings.
    func requestAccess() -> Bool
    /// `region` is in points from the display's top left; `nil` records the whole display.
    func start(region: CGRect?, on display: CGDirectDisplayID) async throws
    /// Finishes the file and returns where it is.
    func stop() async throws -> URL
}

/// Records the screen to a movie in `~/Movies`, capped at 30 minutes, and puts the result on the Shelf.
@MainActor
@Observable
final class ScreenRecorder {
    nonisolated static let maxDuration: Duration = .seconds(30 * 60)

    private(set) var startedAt: Date?
    var isRecording: Bool { startedAt != nil }

    /// Called with the finished movie.
    @ObservationIgnored var onFinish: ((URL) -> Void)?
    @ObservationIgnored var onFail: ((String) -> Void)?
    /// Called when macOS has not given Screen Recording access.
    @ObservationIgnored var onNeedsAccess: (() -> Void)?

    @ObservationIgnored private let recorder: ScreenRecording
    @ObservationIgnored private let shelf: ShelfModel?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let maxDuration: Duration
    @ObservationIgnored private var capTask: Task<Void, Never>?

    init(
        recorder: ScreenRecording, shelf: ShelfModel? = nil, now: @escaping () -> Date = Date.init,
        maxDuration: Duration = ScreenRecorder.maxDuration
    ) {
        self.recorder = recorder
        self.shelf = shelf
        self.now = now
        self.maxDuration = maxDuration
    }

    func start(region: CGRect?) async {
        guard !isRecording else { return }
        guard recorder.hasAccess || recorder.requestAccess() else {
            onNeedsAccess?()
            return
        }
        do {
            try await recorder.start(region: region, on: Self.targetDisplay())
        } catch {
            onFail?(error.localizedDescription)
            return
        }
        startedAt = now()
        capTask = Task { [weak self, maxDuration] in
            try? await Task.sleep(for: maxDuration)
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    func stop() async {
        guard isRecording else { return }
        capTask?.cancel()
        capTask = nil
        startedAt = nil
        do {
            let url = try await recorder.stop()
            shelf?.add([url])
            onFinish?(url)
        } catch {
            onFail?(error.localizedDescription)
        }
    }

    /// The display the island is on: the notched one, or the main one.
    static func targetDisplay() -> CGDirectDisplayID {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number.map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// "Screen Recording 2026-09-29 at 3.45.12 PM.mov", in the Movies folder, never overwriting.
    static func destination(at date: Date, in directory: URL? = nil) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let folder = directory ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        return FileTools.uniqueURL(for: "Screen Recording \(formatter.string(from: date)).mov", in: folder)
    }
}

/// ScreenCaptureKit, on this Mac: the display without MacIsland's own windows, written straight to a movie.
@MainActor
final class SCKScreenRecorder: NSObject, ScreenRecording, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var url: URL?
    private var finished: CheckedContinuation<Void, Never>?
    private var failure: String?

    var hasAccess: Bool { CGPreflightScreenCaptureAccess() }

    func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }

    func start(region: CGRect?, on display: CGDirectDisplayID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.displays.first(where: { $0.displayID == display }) ?? content.displays.first else {
            throw FileToolError.failed("No display was found.")
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: target, excludingApplications: ownApps, exceptingWindows: [])

        let scale = CGFloat(filter.pointPixelScale)
        let area = region ?? CGRect(x: 0, y: 0, width: CGFloat(target.width), height: CGFloat(target.height))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area
        // H.264 wants even dimensions.
        configuration.width = max(2, Int(area.width * scale) / 2 * 2)
        configuration.height = max(2, Int(area.height * scale) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true

        let file = ScreenRecorder.destination(at: Date())
        let output = SCRecordingOutputConfiguration()
        output.outputURL = file
        output.outputFileType = .mov
        output.videoCodecType = .h264
        let recording = SCRecordingOutput(configuration: output, delegate: self)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addRecordingOutput(recording)
        failure = nil
        try await stream.startCapture()
        self.stream = stream
        url = file
    }

    func stop() async throws -> URL {
        guard let stream, let url else { throw FileToolError.failed("Nothing is being recorded.") }
        self.stream = nil
        self.url = nil
        // The movie is complete once the recording output says so.
        await withCheckedContinuation { continuation in
            finished = continuation
            Task {
                do { try await stream.stopCapture() } catch { self.finish(with: error.localizedDescription) }
            }
        }
        if let failure { throw FileToolError.failed(failure) }
        return url
    }

    private func finish(with error: String?) {
        if let error { failure = error }
        finished?.resume()
        finished = nil
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.finish(with: nil) }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.finish(with: error.localizedDescription) }
    }
}

// MARK: - Choosing what to record

/// What the person chose on the picker.
enum RegionSelection: Equatable {
    case cancelled
    case display
    /// In points from the display's top left.
    case region(CGRect)
}

/// A full-screen transparent panel with a crosshair: drag to choose a region, click for the whole display, Esc to cancel.
@MainActor
final class RegionPicker {
    static let shared = RegionPicker()
    /// A drag shorter than this many points is a click.
    nonisolated static let clickTolerance: CGFloat = 4

    private var panel: NSPanel?

    /// The rectangle between two corners, whichever way it was dragged.
    nonisolated static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
    }

    nonisolated static func selection(from start: CGPoint, to end: CGPoint, screenHeight: CGFloat) -> RegionSelection {
        let rect = rect(from: start, to: end)
        if rect.width < clickTolerance && rect.height < clickTolerance { return .display }
        // Down from the top, as ScreenCaptureKit counts.
        return .region(CGRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height))
    }

    func present(completion: @escaping (RegionSelection) -> Void) {
        guard panel == nil else { return }
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let panel = PickerPanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let view = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self, weak panel] selection in
            panel?.orderOut(nil)
            self?.panel = nil
            completion(selection)
        }
        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        NSCursor.crosshair.push()
    }

    private final class PickerPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class PickerView: NSView {
        var onFinish: ((RegionSelection) -> Void)?
        private var start: CGPoint?
        private var current: CGPoint?

        override var acceptsFirstResponder: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            // A faint veil, with the chosen region left clear.
            NSColor.black.withAlphaComponent(0.25).setFill()
            bounds.fill()
            guard let start, let current else { return }
            let rect = RegionPicker.rect(from: start, to: current)
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 1
            border.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            start = convert(event.locationInWindow, from: nil)
            current = start
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            current = convert(event.locationInWindow, from: nil)
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            guard let start else { return }
            let end = convert(event.locationInWindow, from: nil)
            NSCursor.pop()
            onFinish?(RegionPicker.selection(from: start, to: end, screenHeight: bounds.height))
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {  // Esc
                NSCursor.pop()
                onFinish?(.cancelled)
            } else {
                super.keyDown(with: event)
            }
        }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    }
}

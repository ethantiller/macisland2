import AppKit
import AVFoundation
import Observation
import SwiftUI

enum CameraAccess: Equatable {
    case notDetermined, granted, denied
}

enum CameraError: LocalizedError {
    case noCamera

    var errorDescription: String? { "No camera was found." }
}

/// The camera, behind a protocol so tests never open one.
@MainActor
protocol CameraSessionProviding: AnyObject {
    var access: CameraAccess { get }
    func requestAccess() async -> Bool
    /// A running session with one camera on it. Frames only reach a preview layer, never the app.
    func start() async throws -> AVCaptureSession
    func stop()
}

/// A look at yourself before a call. The camera runs only while the mirror is on, and everything is released when it
/// stops.
@MainActor
@Observable
final class CameraMirror {
    private(set) var isOn = false
    private(set) var access: CameraAccess
    /// Set once the camera runs; the preview layer draws it.
    private(set) var session: AVCaptureSession?
    /// The camera could not be opened (none is connected, or another app has it).
    private(set) var isUnavailable = false

    @ObservationIgnored private let provider: CameraSessionProviding

    init(provider: CameraSessionProviding) {
        self.provider = provider
        access = provider.access
    }

    func toggle() async {
        if isOn { stop() } else { await start() }
    }

    private func start() async {
        isOn = true
        isUnavailable = false
        access = provider.access
        if access == .notDetermined {
            access = await provider.requestAccess() ? .granted : .denied
        }
        // Stopped while the permission sheet was up.
        guard isOn, access == .granted else { return }
        do {
            let running = try await provider.start()
            if isOn {
                session = running
            } else {
                provider.stop()
            }
        } catch {
            isUnavailable = true
        }
    }

    func stop() {
        guard isOn || session != nil else { return }
        provider.stop()
        session = nil
        isOn = false
        isUnavailable = false
    }

    static func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// AVFoundation, on this Mac. Start and stop run on a private serial queue, since they block.
@MainActor
final class AVCameraProvider: CameraSessionProviding {
    private let queue = DispatchQueue(label: "com.ethantiller.MacIsland.camera")
    private var session: AVCaptureSession?

    var access: CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start() async throws -> AVCaptureSession {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external], mediaType: .video, position: .unspecified
        )
        // The built-in camera first, then Continuity and external ones.
        guard let device = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? discovery.devices.first
        else { throw CameraError.noCamera }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.noCamera }
        session.addInput(input)
        self.session = session
        await withCheckedContinuation { continuation in
            queue.async {
                session.startRunning()
                continuation.resume()
            }
        }
        return session
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        queue.async { session.stopRunning() }
    }
}

/// The camera picture, mirrored like a mirror. It is a preview layer only, so no frames reach the app.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        if let connection = view.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = previewLayer
        }

        required init?(coder: NSCoder) { nil }
    }
}

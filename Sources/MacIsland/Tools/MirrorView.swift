import SwiftUI

/// The Tools tab while the mirror is on: the camera, and Ring Light and Done beside it.
struct MirrorView: View {
    let viewModel: IslandViewModel

    private var mirror: CameraMirror { viewModel.mirror }
    private var light: RingLight { viewModel.ringLight }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Metrics.rowSpacing + 4) {
            preview
                .frame(width: Theme.Metrics.mirrorWidth, height: Theme.Metrics.mirrorHeight)
                .background(Color.black, in: shape)
                .clipShape(shape)
            VStack(spacing: 10) {
                ControlButton(title: "Ring Light", systemImage: "lightbulb.fill", isOn: light.isOn) {
                    withAnimation(Theme.Motion.resize) { light.toggle() }
                }
                if light.isOn {
                    IslandSlider(value: light.brightness, label: "Ring Light Brightness", onChange: { light.brightness = $0 })
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                ChipButton(title: "Done", fillsWidth: true) { viewModel.stopMirror() }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.widgetRadius, style: .continuous)
    }

    @ViewBuilder
    private var preview: some View {
        if mirror.access == .denied {
            problem("Camera access is off.", action: ChipButton(title: "Open Settings", action: CameraMirror.openCameraSettings))
        } else if mirror.isUnavailable {
            problem("No camera found.", action: nil as ChipButton?)
        } else if let session = mirror.session {
            CameraPreview(session: session)
                .accessibilityLabel("Camera preview")
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func problem(_ text: String, action: ChipButton?) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(Theme.Typography.bodyEmphasized)
                .foregroundStyle(Theme.Palette.secondary)
            if let action { action }
        }
    }
}

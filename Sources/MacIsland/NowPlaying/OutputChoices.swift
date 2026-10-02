import CoreAudio
import SwiftUI

struct CurrentOutputChip: View {
    let outputs: AudioOutputs
    @Binding var isOpen: Bool

    @Environment(\.mediaNamespace) private var namespace

    private var currentOutput: AudioOutputs.Device? { outputs.currentDevice }

    var body: some View {
        Button {
            withAnimation(Theme.Motion.resize) { isOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                if let currentOutput {
                    outputGlyph(currentOutput)
                } else {
                    Image(systemName: "hifispeaker")
                }
                Text(currentOutput?.name ?? "Audio Output")
                    .lineLimit(1)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(Theme.Typography.bodyEmphasized)
            .foregroundStyle(Theme.Palette.primary)
            .padding(.horizontal, 9)
            .frame(height: Theme.Metrics.outputRowHeight)
            .frame(maxWidth: Theme.Metrics.outputPillMaxWidth)
            .background(Theme.Palette.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(IslandButtonStyle())
        .help(isOpen ? "Hide Audio Outputs" : "Choose Audio Output")
        .accessibilityLabel("Audio Output")
        .accessibilityValue(currentOutput?.name ?? "Unknown")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    @ViewBuilder
    private func outputGlyph(_ output: AudioOutputs.Device) -> some View {
        if let namespace {
            Image(systemName: output.systemImage)
                .matchedGeometryEffect(id: "output-\(output.id)", in: namespace)
        } else {
            Image(systemName: output.systemImage)
        }
    }
}

struct AudioOutputButton: View {
    let currentDeviceID: AudioDeviceID
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.mediaNamespace) private var namespace

    var body: some View {
        Button { action() } label: {
            outputGlyph
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSelected ? Theme.Palette.inverse : Theme.Palette.primary)
                .frame(width: Theme.Metrics.hitTarget, height: Theme.Metrics.hitTarget)
                .background(isSelected ? Theme.Palette.primary : Theme.Palette.none, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
        .help(isSelected ? "Hide Audio Outputs" : "Show Audio Outputs")
        .accessibilityLabel("Audio Output and Volume")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var outputGlyph: some View {
        if let namespace {
            Image(systemName: "airplayaudio")
                .matchedGeometryEffect(id: "output-\(currentDeviceID)", in: namespace)
        } else {
            Image(systemName: "airplayaudio")
        }
    }
}

enum OutputSatelliteOrder {
    static func replacingSelected(
        _ selected: AudioDeviceID, with previousDefault: AudioDeviceID, in order: [AudioDeviceID]
    ) -> [AudioDeviceID] {
        var result = order
        guard let index = result.firstIndex(of: selected) else { return result }
        result[index] = previousDefault
        return result
    }
}

struct OutputList: View {
    let outputs: AudioOutputs
    let bluetooth: BluetoothDevices
    @Binding var isOpen: Bool
    var maxRows = Theme.Metrics.peekOutputMaxRows

    private var connected: [AudioOutputs.Device] {
        outputs.currentDevice.map { [$0] + outputs.otherDevices } ?? outputs.devices
    }

    private var rowCount: Int {
        max(connected.count + bluetooth.notConnected.count, 1)
    }

    private var height: CGFloat {
        CGFloat(min(rowCount, max(1, maxRows))) * Theme.Metrics.outputRowHeight
            + (bluetooth.notConnected.isEmpty ? 0 : Theme.Metrics.outputCaptionHeight)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(connected) { device in
                    OutputChoiceRow(
                        title: device.name,
                        systemImage: device.systemImage,
                        isSelected: device.id == outputs.defaultDeviceID
                    ) {
                        outputs.select(device)
                        withAnimation(Theme.Motion.resize) { isOpen = false }
                    }
                    .contextMenu {
                        if let paired = pairedDevice(for: device) {
                            Button("Disconnect") { bluetooth.disconnect(paired) }
                        }
                    }
                }

                if !bluetooth.notConnected.isEmpty {
                    Text("Not Connected")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.outputCaptionHeight, alignment: .leading)
                        .padding(.horizontal, 9)

                    ForEach(bluetooth.notConnected) { device in
                        OutputChoiceRow(title: device.name, systemImage: "headphones", isSelected: false) {
                            Task { await bluetooth.connect(device) }
                            withAnimation(Theme.Motion.resize) { isOpen = false }
                        }
                    }
                }

                if connected.isEmpty && bluetooth.notConnected.isEmpty {
                    Text("No Audio Outputs")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.outputRowHeight)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.innerRadius, style: .continuous))
        .reportsScrollArea(.vertical)
    }

    private func pairedDevice(for device: AudioOutputs.Device) -> PairedDevice? {
        guard device.isBluetooth else { return nil }
        return bluetooth.devices.first { $0.name == device.name && $0.isConnected }
    }
}

struct OutputSatellites: View {
    fileprivate struct Choice: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let isConnected: Bool
        let action: () -> Void
    }

    let outputs: AudioOutputs
    let bluetooth: BluetoothDevices
    let maxCount: Int
    let isVisible: Bool
    let onHover: (String, Bool) -> Void
    @State private var orderedAudioIDs: [AudioDeviceID] = []

    private var orderedAudioDevices: [AudioOutputs.Device] {
        let lookup = Dictionary(uniqueKeysWithValues: outputs.devices.map { ($0.id, $0) })
        var ordered = orderedAudioIDs.compactMap { lookup[$0] }.filter { $0.id != outputs.defaultDeviceID }
        let known = Set(ordered.map(\.id))
        ordered += outputs.otherDevices.filter { !known.contains($0.id) }
        return ordered
    }

    private var choices: [Choice] {
        let connected = orderedAudioDevices.prefix(maxCount).map { device in
            Choice(
                id: "output-\(device.id)", title: device.name, systemImage: device.systemImage,
                isConnected: true, action: { outputs.select(device) })
        }
        let remaining = max(0, maxCount - connected.count)
        let notConnected = bluetooth.notConnected.prefix(remaining).map { device in
            Choice(
                id: "bluetooth-\(device.id)", title: device.name, systemImage: "headphones",
                isConnected: false, action: { Task { await bluetooth.connect(device) } })
        }
        return Array(connected) + Array(notConnected)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var shownIDs: Set<String> = []
    @State private var expandedIDs: Set<String> = []
    @State private var textWidths: [String: CGFloat] = [:]

    private func width(of choice: Choice) -> CGFloat {
        expandedIDs.contains(choice.id) ? OutputPill.width(textWidth: textWidths[choice.id] ?? 0) : Theme.Metrics.outputSatelliteSize
    }

    var body: some View {
        let choices = self.choices
        Group {
            // Nothing is drawn once the dots have gone back in: glass left in the tree would still show.
            if isVisible || !shownIDs.isEmpty { column(choices) }
        }
        .animation(Theme.Motion.resize, value: outputs.defaultDeviceID)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .onAppear {
            if orderedAudioIDs.isEmpty { orderedAudioIDs = outputs.otherDevices.map(\.id) }
            syncShown(choices, animated: false)
        }
        .onChange(of: isVisible) { _, visible in
            if visible && orderedAudioIDs.isEmpty {
                orderedAudioIDs = outputs.otherDevices.map(\.id)
            }
            if !visible { onHover("", false) }
            syncShown(self.choices, animated: true)
        }
        .onChange(of: choices.map(\.id)) { _, _ in syncShown(self.choices, animated: false) }
        .onChange(of: outputs.defaultDeviceID) { oldID, newID in
            guard oldID != newID else { return }
            if orderedAudioIDs.isEmpty { orderedAudioIDs = outputs.otherDevices.map(\.id) }
            orderedAudioIDs = OutputSatelliteOrder.replacingSelected(newID, with: oldID, in: orderedAudioIDs)
        }
    }

    @ViewBuilder
    private func column(_ choices: [Choice]) -> some View {
        let stack = VStack(alignment: .leading, spacing: Theme.Metrics.outputSatelliteSpacing) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { _, choice in
                OutputSatelliteButton(
                    choice: choice,
                    isShown: shownIDs.contains(choice.id),
                    isExpanded: expandedIDs.contains(choice.id),
                    pillWidth: width(of: choice),
                    glassNamespace: glassNamespace,
                    onMeasure: { textWidths[choice.id] = $0 },
                    onHover: { hovering in
                        withAnimation(Theme.Motion.resize) {
                            if hovering { expandedIDs.insert(choice.id) } else { expandedIDs.remove(choice.id) }
                        }
                        onHover(choice.id, hovering)
                    },
                    onSelect: {
                        expandedIDs.remove(choice.id)
                        onHover(choice.id, false)
                        choice.action()
                    })
            }
        }
        // Liquid Glass bubbles beside the island, not inside it: they merge and part like drops as they swell and move.
        GlassEffectContainer(spacing: Theme.Metrics.outputSatelliteGap) { stack }
    }

    /// Shows or hides every dot: staggered going out, in reverse coming back, a short fade under Reduce Motion.
    private func syncShown(_ choices: [Choice], animated: Bool) {
        let target = isVisible ? Set(choices.map(\.id)) : []
        guard target != shownIDs else { return }
        guard animated else { shownIDs = target; return }
        for (index, choice) in choices.enumerated() {
            let wants = target.contains(choice.id)
            guard wants != shownIDs.contains(choice.id) else { continue }
            let animation = reduceMotion
                ? Animation.easeOut(duration: 0.16)
                : (isVisible ? Theme.Motion.open : Theme.Motion.close).delay(Double(index) * 0.035)
            withAnimation(animation) {
                if wants { shownIDs.insert(choice.id) } else { shownIDs.remove(choice.id) }
            }
        }
        shownIDs.formIntersection(Set(choices.map(\.id)))
    }
}

private struct OutputSatelliteButton: View {
    let choice: OutputSatellites.Choice
    let isShown: Bool
    let isExpanded: Bool
    let pillWidth: CGFloat
    let glassNamespace: Namespace.ID
    let onMeasure: (CGFloat) -> Void
    let onHover: (Bool) -> Void
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mediaNamespace) private var namespace

    private var size: CGFloat { Theme.Metrics.outputSatelliteSize }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                satelliteGlyph
                if isExpanded {
                    Text(choice.title)
                        .font(Theme.Typography.bodyEmphasized)
                        .lineLimit(1)
                        .frame(maxWidth: Theme.Metrics.outputPillMaxWidth - 47, alignment: .leading)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .frame(width: pillWidth, height: size, alignment: .leading)
            .glassEffect(isShown ? Glass.regular.tint(Theme.Palette.satelliteTint) : Glass.identity, in: Capsule())
            .glassEffectID(choice.id, in: glassNamespace)
            .environment(\.colorScheme, .dark)
            .contentShape(Capsule())
        }
        .buttonStyle(IslandButtonStyle())
        .overlay(alignment: .leading) { measurement }
        .opacity(opacity)
        .scaleEffect(reduceMotion || isShown ? 1 : 0.6, anchor: .leading)
        .offset(x: reduceMotion || isShown ? 0 : -(size + Theme.Metrics.outputSatelliteGap))
        .onHover(perform: onHover)
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityValue(choice.isConnected ? "" : "Not Connected")
    }

    /// Hidden, always laid out, so the pill knows its name's width before it is hovered.
    private var measurement: some View {
        Text(choice.title)
            .font(Theme.Typography.bodyEmphasized)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onMeasure($0) }
            .accessibilityHidden(true)
    }

    /// A hidden dot draws nothing: its glyph would otherwise sit over the island, with no bubble behind it.
    private var opacity: Double { isShown ? 1 : 0 }

    @ViewBuilder
    private var satelliteGlyph: some View {
        if choice.isConnected, let namespace {
            Image(systemName: choice.systemImage)
                .matchedGeometryEffect(id: choice.id, in: namespace)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        } else {
            Image(systemName: choice.systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
    }
}

private struct OutputChoiceRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Glyph(systemName: systemImage)
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.primary)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.outputRowHeight)
            .background(isSelected ? Theme.Palette.fill : Theme.Palette.none, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
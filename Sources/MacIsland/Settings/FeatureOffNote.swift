import SwiftUI

private struct OpenFeaturesKey: EnvironmentKey {
    static let defaultValue: (Feature) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Goes to a feature's row in the Features pane. Set by the Settings window.
    var openFeatures: (Feature) -> Void {
        get { self[OpenFeaturesKey.self] }
        set { self[OpenFeaturesKey.self] = newValue }
    }
}

/// A line for a pane whose feature is off: it says so, and goes to the switch. Nothing while the feature is on.
struct FeatureOffNote: View {
    let settings: AppSettings
    let feature: Feature
    @Environment(\.openFeatures) private var openFeatures

    var body: some View {
        if !settings.isOn(feature) {
            HStack {
                Text("\(feature.title) is turned off in Features.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Open Features") { openFeatures(feature) }
            }
        }
    }
}

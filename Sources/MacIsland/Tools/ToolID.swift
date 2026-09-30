/// Every tool the Tools tab can show. The person pins which ones sit in the row.
enum ToolID: String, CaseIterable, Identifiable {
    case keepAwake
    case lowPower
    case ringLight
    case muteMic
    case pickColor
    case screenshot
    case focus
    case cleanKeyboard
    case lockScreen

    var id: String { rawValue }

    /// Low Power stays behind More: the low-battery banner already offers it.
    static let defaultPins: [ToolID] = [.keepAwake, .ringLight, .muteMic, .screenshot, .pickColor, .focus]
}

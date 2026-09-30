/// Every tool the Tools tab can show. The person pins which ones sit in the row.
enum ToolID: String, CaseIterable, Identifiable, Codable {
    case keepAwake
    case ringLight
    case muteMic
    case pickColor
    case screenshot
    case focus
    case cleanKeyboard
    case mirror
    case recordScreen

    var id: String { rawValue }

    static let defaultPins: [ToolID] = [.keepAwake, .ringLight, .muteMic, .screenshot, .pickColor, .focus]

    /// Every tool with the default pins first: what fills a Quick Tools slot nobody chose.
    static let fillOrder: [ToolID] = defaultPins + allCases.filter { !defaultPins.contains($0) }
}

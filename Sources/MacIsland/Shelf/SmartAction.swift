import Foundation

/// The one useful thing a copied piece of text offers: open a link, copy a color as RGB, write to an address.
enum SmartAction: Equatable {
    case openURL(URL)
    case color(hex: String, rgb: String)
    case email(String)

    var title: String {
        switch self {
        case .openURL: "Open"
        case .color: "Copy RGB"
        case .email: "New Email"
        }
    }

    private static let hexPattern = try! NSRegularExpression(pattern: #"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$"#)
    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Only text that is entirely a link, address, or color counts, not a sentence that contains one.
    static func detect(in text: String) -> SmartAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
        let whole = NSRange(trimmed.startIndex..., in: trimmed)

        if hexPattern.firstMatch(in: trimmed, range: whole) != nil { return color(from: trimmed) }

        guard let match = linkDetector.firstMatch(in: trimmed, range: whole), match.range == whole,
              let url = match.url
        else { return nil }
        switch url.scheme?.lowercased() {
        case "mailto": return .email(trimmed)
        case "http", "https": return .openURL(url)
        default: return nil
        }
    }

    private static func color(from text: String) -> SmartAction? {
        var digits = String(text.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        let red = (value >> 16) & 0xFF, green = (value >> 8) & 0xFF, blue = value & 0xFF
        return .color(hex: "#" + digits.uppercased(), rgb: "rgb(\(red), \(green), \(blue))")
    }
}

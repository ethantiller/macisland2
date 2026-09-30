import AppKit

/// Picks the most vivid color in album art and lifts it until it reads on black.
enum ArtworkAccent {
    /// WCAG relative luminance of at least 0.3 gives ≥ 7:1 contrast against black.
    static let minimumLuminance: CGFloat = 0.3

    static func color(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var best: NSColor?
        var bestScore: CGFloat = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let color = NSColor(
                srgbRed: CGFloat(pixels[index]) / 255,
                green: CGFloat(pixels[index + 1]) / 255,
                blue: CGFloat(pixels[index + 2]) / 255,
                alpha: 1
            )
            let score = color.saturationComponent * color.brightnessComponent
            if score > bestScore {
                bestScore = score
                best = color
            }
        }
        return best.flatMap(legible)
    }

    /// Returns nil for near-gray colors (use white instead); otherwise mixes toward white
    /// until the color meets `minimumLuminance`.
    static func legible(_ color: NSColor) -> NSColor? {
        guard let srgb = color.usingColorSpace(.sRGB), srgb.saturationComponent >= 0.25 else { return nil }
        var result = srgb
        while luminance(of: result) < minimumLuminance {
            result = result.blended(withFraction: 0.12, of: .white)?.usingColorSpace(.sRGB) ?? .white
        }
        return result
    }

    static func luminance(of color: NSColor) -> CGFloat {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 1 }
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent) + 0.7152 * linear(srgb.greenComponent) + 0.0722 * linear(srgb.blueComponent)
    }
}

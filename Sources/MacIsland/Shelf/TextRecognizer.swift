import CoreGraphics
import Vision

/// The text (and QR payloads) found in an image.
struct RecognizedText: Equatable, Sendable {
    var lines: [String]
    var barcodePayloads: [String]

    var isEmpty: Bool { lines.isEmpty && barcodePayloads.isEmpty }

    /// Everything, one item per line: the text first, then any QR payloads.
    var joined: String { (lines + barcodePayloads).joined(separator: "\n") }

    /// Reading order for boxes in Vision's coordinates (the origin is bottom left): top to bottom, and
    /// left to right for boxes on the same line.
    nonisolated static func ordered(_ boxes: [(text: String, box: CGRect)]) -> [String] {
        let sorted = boxes.sorted { $0.box.midY > $1.box.midY }
        var rows: [[(text: String, box: CGRect)]] = []
        for item in sorted {
            if let first = rows.last?.first, abs(first.box.midY - item.box.midY) < min(first.box.height, item.box.height) / 2 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }
}

protocol TextRecognizing: Sendable {
    func recognize(_ image: CGImage) async throws -> RecognizedText
}

/// Vision, on this Mac: accurate recognition with language correction and automatic language.
struct VisionTextRecognizer: TextRecognizing {
    func recognize(_ image: CGImage) async throws -> RecognizedText {
        var text = RecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.automaticallyDetectsLanguage = true
        var codes = DetectBarcodesRequest()
        codes.symbologies = [.qr]

        let observations = try await text.perform(on: image)
        let boxes: [(text: String, box: CGRect)] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, observation.boundingBox.cgRect)
        }
        let payloads = ((try? await codes.perform(on: image)) ?? []).compactMap(\.payloadString)
        return RecognizedText(lines: RecognizedText.ordered(boxes), barcodePayloads: payloads)
    }
}

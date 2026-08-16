import AppKit
import CoreGraphics
import Vision

enum TextRecognitionError: Error, LocalizedError {
    case noTextFound
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            "No readable text in that selection."
        case .recognitionFailed(let reason):
            "Text recognition failed: \(reason)"
        }
    }
}

/// Vision OCR over a `CGImage`. No capture, no clipboard, no UI.
enum TextRecognitionService {
    /// Vision's `perform` is synchronous and can run for hundreds of milliseconds on
    /// a dense screenshot, so it never touches the main actor.
    private static let queue = DispatchQueue(label: "me.whiz.app.ocr", qos: .userInitiated)

    static func recognizeText(in image: CGImage) async throws -> String {
        let lines: [String] = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true

                do {
                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    try handler.perform([request])
                    let results = request.results ?? []
                    // Vision returns observations in reading order; keep it.
                    continuation.resume(returning: results.compactMap { $0.topCandidates(1).first?.string })
                } catch {
                    continuation.resume(throwing: TextRecognitionError.recognitionFailed(error.localizedDescription))
                }
            }
        }

        let text = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw TextRecognitionError.noTextFound }
        return text
    }

    #if canImport(AppKit)
    static func recognizeText(in image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw TextRecognitionError.recognitionFailed("Could not get CGImage from NSImage.")
        }
        return try await recognizeText(in: cgImage)
    }
    #endif
}

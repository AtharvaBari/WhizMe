import Foundation
import Observation
import os

/// Orchestrates Text Extractor: permission gate → region selection → capture →
/// recognition → clipboard → banner. Holds the state the menu bar renders and does
/// none of the low-level work itself.
@MainActor
@Observable
final class OCRManager {
    private(set) var isCapturing = false
    private(set) var lastText: String?
    /// User-presentable failure from the most recent run, shown inline in the menu.
    private(set) var lastError: String?

    @ObservationIgnored private let permissions: PermissionManager
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "OCR")

    init(permissions: PermissionManager) {
        self.permissions = permissions
    }

    func captureText() {
        guard !isCapturing else { return }
        isCapturing = true
        Task { await run() }
    }

    private func run() async {
        defer { isCapturing = false }

        // Re-read rather than trusting the cache: the user may have granted access in
        // System Settings since the last poll.
        permissions.refresh()
        guard permissions.state(for: .screenRecording).isGranted else {
            permissions.request(.screenRecording)
            lastError = ScreenCaptureError.permissionDenied.localizedDescription
            return
        }

        guard let region = await RegionSelectionOverlay.shared.selectRegion() else {
            lastError = nil // deliberate cancel, not a failure
            return
        }

        do {
            let image = try await ScreenCaptureService.captureImage(in: region)
            let text = try await TextRecognitionService.recognizeText(in: image)

            lastText = text
            lastError = nil
            PasteboardService.copy(text)
            NotificationService.shared.post(
                title: "Text copied",
                body: "Copied \(text.count) characters to the clipboard."
            )
        } catch {
            log.error("Text extraction failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            NotificationService.shared.post(
                title: "Text Extractor failed",
                body: error.localizedDescription
            )
        }
    }
}

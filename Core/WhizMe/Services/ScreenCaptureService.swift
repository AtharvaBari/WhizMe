import CoreGraphics
import ScreenCaptureKit
import os

enum ScreenCaptureError: Error, LocalizedError {
    case permissionDenied
    case noDisplayFound
    case emptyRegion
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "WhizMe needs Screen Recording access to read the screen. Grant it in System Settings, then relaunch WhizMe."
        case .noDisplayFound:
            "That region isn't on any connected display."
        case .emptyRegion:
            "Drag a larger area to capture."
        case .captureFailed(let reason):
            "Screen capture failed: \(reason)"
        }
    }
}

/// Turns a screen rectangle into pixels. Nothing else — no selection UI, no OCR.
///
/// Input rects are in CoreGraphics display coordinates (top-left origin), which is
/// what `RegionSelectionOverlay` returns.
enum ScreenCaptureService {
    private static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "ScreenCapture")

    static func captureImage(in rect: CGRect) async throws -> CGImage {
        guard rect.width >= 1, rect.height >= 1 else { throw ScreenCaptureError.emptyRegion }

        // Without the grant, macOS does not fail the capture — it silently returns an
        // image containing only the desktop picture. That would surface as a baffling
        // "no text found", so refuse up front instead.
        guard CGPreflightScreenCaptureAccess() else { throw ScreenCaptureError.permissionDenied }

        do {
            return try await captureUsingScreenCaptureKit(rect)
        } catch {
            log.error("ScreenCaptureKit failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Supported path

    private static func captureUsingScreenCaptureKit(_ rect: CGRect) async throws -> CGImage {
        let displayID = try displayID(containing: rect)

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.noDisplayFound
        }

        // sourceRect is relative to the display's own top-left corner, not the global
        // desktop, so subtract the display's origin.
        let bounds = CGDisplayBounds(displayID)
        let localRect = CGRect(
            x: rect.minX - bounds.minX,
            y: rect.minY - bounds.minY,
            width: rect.width,
            height: rect.height
        )

        // Capture at native pixel density: on a Retina display, sampling at point
        // resolution halves the glyph height and measurably hurts OCR accuracy.
        let scale = backingScale(for: displayID)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localRect
        configuration.width = max(1, Int((localRect.width * scale).rounded()))
        configuration.height = max(1, Int((localRect.height * scale).rounded()))
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.scalesToFit = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private static func displayID(containing rect: CGRect) throws -> CGDirectDisplayID {
        var displayID = CGDirectDisplayID()
        var matchCount: UInt32 = 0
        let status = CGGetDisplaysWithRect(rect, 1, &displayID, &matchCount)
        guard status == .success, matchCount > 0 else {
            throw ScreenCaptureError.noDisplayFound
        }
        return displayID
    }

    private static func backingScale(for displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}

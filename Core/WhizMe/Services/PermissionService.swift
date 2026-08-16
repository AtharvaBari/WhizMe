import AppKit
// `kAXTrustedCheckOptionPrompt` is `extern CFStringRef` (not `const`), so Swift imports
// it as a mutable global `var` and strict concurrency rejects every reference to it.
// The constant is immutable in practice, so the import is marked pre-concurrency
// rather than mirroring the literal key string here and hoping it never changes.
@preconcurrency import ApplicationServices
import CoreGraphics
import os

/// Thin wrapper over the two TCC APIs WhizMe depends on: Accessibility and
/// Screen Recording.
///
/// Deliberately stateless. Every call is a straight syscall with no caching, so a
/// permission the user just flipped in System Settings is reported the instant it is
/// asked about. Remembering answers over time — and knowing *when* to ask again —
/// is `PermissionManager`'s job.
@MainActor
enum PermissionService {
    private static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "Permissions")

    /// Reads live status. Both APIs answer synchronously and authoritatively, so
    /// `.unknown` is never returned here; it stays reserved for a future permission
    /// that genuinely cannot be probed without side effects.
    static func state(for permission: SystemPermission) -> PermissionState {
        switch permission {
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .denied
        case .screenRecording:
            // Preflight is the read-only sibling of `CGRequestScreenCaptureAccess()`:
            // it reports status without ever showing a prompt, which is what makes it
            // safe to call on a 2s polling loop.
            CGPreflightScreenCaptureAccess() ? .granted : .denied
        }
    }

    /// Shows the "…would like to control this computer" system prompt.
    ///
    /// macOS only presents it once per app identity: after the user dismisses it, the
    /// call becomes a silent no-op forever. Callers must therefore be ready to fall
    /// back to `openSettings(for:)`.
    static func requestAccessibility() {
        // `kAXTrustedCheckOptionPrompt` is an unretained CFString constant, so it has
        // to be unwrapped through `takeUnretainedValue()` before it can be bridged
        // into a Swift dictionary key — taking a retained value here would over-release.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary

        // The return value is the trust state *before* the user answers the sheet, not
        // the outcome of it, so it is worthless to us — the grant is observed by polling.
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Shows the Screen Recording system prompt.
    ///
    /// Same once-per-app-lifetime rule as Accessibility. Note that the grant does not
    /// take effect in the running process — see `SystemPermission.requiresRelaunch`.
    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func request(_ permission: SystemPermission) {
        switch permission {
        case .accessibility: requestAccessibility()
        case .screenRecording: requestScreenRecording()
        }
    }

    /// Opens the matching Privacy & Security pane. The URL lives on the model so the
    /// deep links are declared exactly once.
    static func openSettings(for permission: SystemPermission) {
        guard NSWorkspace.shared.open(permission.settingsURL) else {
            // A refused deep link is not fatal: the onboarding copy still tells the
            // user where to go, so log it and carry on.
            log.error("Could not open System Settings for \(permission.rawValue, privacy: .public)")
            return
        }
    }
}

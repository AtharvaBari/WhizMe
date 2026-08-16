import AppKit
import Observation
import SwiftUI
import os

/// Runs a keyboard-cleaning session: every key is swallowed until the user clicks the
/// overlay's button with the trackpad.
///
/// The exit is deliberately pointer-only. A keyboard shortcut to stop would have to
/// survive the very block it is cancelling, and any key that still works is a key that
/// fires while being wiped.
@MainActor
@Observable
final class CleanKeyboardManager {
    private(set) var isCleaning = false
    /// Surfaced in the UI when the block could not start — almost always a missing
    /// Accessibility grant.
    private(set) var lastError: String?

    @ObservationIgnored private let permissions: PermissionManager
    @ObservationIgnored private let overlay = OverlayPresenter()
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "CleanKeyboard")

    /// Called when a session starts, so the screen blackout can stand down. Both at
    /// once would leave a black screen whose only exit is a key that is being swallowed.
    @ObservationIgnored var onWillStart: (() -> Void)?

    init(permissions: PermissionManager) {
        self.permissions = permissions
    }

    func toggle() {
        isCleaning ? stop() : start()
    }

    func start() {
        guard !isCleaning else { return }

        permissions.refresh()
        guard permissions.state(for: .accessibility).isGranted else {
            permissions.request(.accessibility)
            lastError = "WhizMe needs Accessibility access to switch the keyboard off. Grant it in System Settings, then try again."
            return
        }

        onWillStart?()

        guard KeyboardBlockService.shared.begin() else {
            lastError = "macOS refused to intercept the keyboard. Check Accessibility access and try again."
            return
        }

        lastError = nil
        isCleaning = true
        overlay.present(acceptsKeys: false) { [weak self] in
            CleanKeyboardOverlay { self?.stop() }
        }
    }

    func stop() {
        guard isCleaning else { return }

        KeyboardBlockService.shared.end()
        overlay.dismiss()
        isCleaning = false
    }
}

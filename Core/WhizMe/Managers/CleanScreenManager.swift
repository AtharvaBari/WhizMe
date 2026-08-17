import AppKit
import Observation
import SwiftUI

/// Blacks out every display so the screen can be wiped, until Escape or Return.
///
/// A black window rather than turning the backlight off: the display stays awake, so
/// nothing re-lights halfway through the wipe and no key has to be pressed to bring the
/// panel back — only to dismiss the sheet.
@MainActor
@Observable
final class CleanScreenManager {
    private(set) var isCleaning = false

    @ObservationIgnored private let overlay = OverlayPresenter()
    @ObservationIgnored private var keyMonitor: Any?

    /// Called when a session starts, so the keyboard block can stand down — its swallow
    /// would eat the very keys that dismiss this.
    @ObservationIgnored var onWillStart: (() -> Void)?

    func toggle() {
        isCleaning ? stop() : start()
    }

    func start() {
        guard !isCleaning else { return }

        onWillStart?()

        // Present first: the key monitor below swallows every keystroke that is not
        // Escape or Return, so installing it without a visible overlay would eat the
        // user's typing with nothing on screen to explain why.
        guard overlay.present(acceptsKeys: true, content: { CleanScreenOverlay() }) else {
            return
        }

        isCleaning = true

        // A local monitor rather than the view's `keyDown`: it fires wherever focus
        // ends up among the per-display windows, so Escape works on any screen.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 Escape, 36 Return, 76 keypad Enter.
            guard event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 76 else {
                // Everything else is ignored while the sheet is up, so a stray press
                // during the wipe does not reach the app underneath.
                return nil
            }
            MainActor.assumeIsolated { self?.stop() }
            return nil
        }
    }

    func stop() {
        guard isCleaning else { return }

        removeMonitor()
        overlay.dismiss()
        isCleaning = false
    }

    private func removeMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}

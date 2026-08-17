import AppKit
import SwiftUI

/// Presents Settings in a standalone `NSWindow`.
///
/// ## Why this exists instead of SwiftUI's `Settings` scene
///
/// `NSApp.sendAction(Selector(("showSettingsWindow:")), …)` does not work in this app.
/// It finds a target and returns `true`, and no window ever appears — verified with the
/// app active and the policy raised to `.regular`, so neither is the cause. The scene
/// simply is never realised: `WhizMeApp` declares `Settings` as its only scene, and an
/// `LSUIElement` app with no window-bearing scene never connects it.
///
/// That broke every route into Settings, including the menu bar's own "Settings…" item.
/// Hosting the view directly is the same approach `OnboardingPresenter` already takes,
/// and for the same underlying reason.
@MainActor
final class SettingsPresenter: NSObject {
    static let shared = SettingsPresenter()

    private var window: NSWindow?

    private override init() {}

    var isPresenting: Bool { window != nil }

    /// - Parameter section: which page to open on. Defaults to Home, which is what the
    ///   first-run sequence wants to show.
    func present(environment: AppEnvironment, section: SettingsSection = .home) {
        if let window {
            bringToFront(window)
            return
        }

        let root = SettingsView(initialSection: section)
            .environment(environment)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.settingsWidth, height: Metrics.settingsHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppInfo.name) Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.delegate = self
        window.center()
        // `SettingsWindowStyler`, inside the view, hides the title bar and registers the
        // window with `AppActivationManager` — so the chrome and the activation policy
        // are handled exactly as they were under the SwiftUI scene.

        self.window = window
        bringToFront(window)
    }

    func dismiss() {
        window?.close()
    }

    private func bringToFront(_ window: NSWindow) {
        // Activation policy has one owner; promoting here would fight it.
        AppActivationManager.shared.present(window)
    }
}

extension SettingsPresenter: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

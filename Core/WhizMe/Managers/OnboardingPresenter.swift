import AppKit
import SwiftUI

/// Presents the permissions walkthrough in a standalone `NSWindow`.
///
/// A SwiftUI `Window` scene would be tidier, but an `LSUIElement` app has no window
/// from which to call `openWindow` at launch, and `NSApplicationDelegate` has no
/// access to the SwiftUI environment. Hosting the view directly keeps launch-time
/// presentation possible and lets us control activation policy around it.
@MainActor
final class OnboardingPresenter: NSObject {
    static let shared = OnboardingPresenter()

    private var window: NSWindow?
    private var preferences: PreferencesManager?

    private override init() {}

    func present(environment: AppEnvironment) {
        if let window {
            bringToFront(window)
            return
        }
        preferences = environment.preferences

        let root = PermissionsOnboardingView()
            .environment(environment)
            .environment(\.dismissOnboarding) { [weak self] in
                self?.dismiss()
            }

        let window = NSWindow(
            // Must match the view's own width, or the hosting view lays out to one size
            // and the window frames another — the content ends up off-centre.
            contentRect: NSRect(x: 0, y: 0, width: Metrics.onboardingWidth, height: Metrics.onboardingHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to \(AppInfo.name)"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.delegate = self
        window.center()

        self.window = window
        bringToFront(window)
    }

    func dismiss() {
        // Routed through `close()` so the teardown in `windowWillClose` runs whether
        // the user hit Done, Skip, or the red close button.
        window?.close()
    }

    private func bringToFront(_ window: NSWindow) {
        // Activation policy is owned centrally. Dropping it back to `.accessory` from
        // here used to deactivate the whole app even when the Settings window was still
        // open, which threw focus to whatever app happened to be next in the stack.
        AppActivationManager.shared.present(window)
    }
}

extension OnboardingPresenter: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Closing by any route counts as "seen", including the red button — otherwise
        // dismissing the window would re-summon it on every launch.
        preferences?.hasCompletedOnboarding = true
        preferences = nil
        window = nil
        // No policy change here: AppActivationManager sees this window close and only
        // demotes the app once nothing else is on screen.
    }
}

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
    private var chromeState: OnboardingChromeState?

    private override init() {}

    func present(environment: AppEnvironment) {
        if let window {
            bringToFront(window)
            return
        }
        preferences = environment.preferences

        let chromeState = OnboardingChromeState()
        self.chromeState = chromeState

        let root = OnboardingWindowChrome(state: chromeState) {
            PermissionsOnboardingView()
        }
        .environment(environment)
        .environment(\.dismissOnboarding) { [weak self] in
            self?.dismiss()
        }

        // The card, its corners, and its shadow are all drawn by
        // `OnboardingWindowChrome`, so every piece of system chrome is switched off
        // below. A stock titled window would put traffic lights and an empty title bar
        // over the first thing a new user ever sees.
        //
        // Still `.titled` rather than `.borderless`, though. A borderless window is not
        // exposed to the accessibility API as a window at all — VoiceOver cannot reach
        // it, and it goes missing from Mission Control and window cycling. Keeping the
        // style and hiding its parts gets the same pixels without that cost.
        //
        // The content rect is the card plus a transparent margin on every side, because
        // the shadow is part of the SwiftUI content and needs somewhere to fall. Sizing
        // it to the card alone clips the shadow at the card's edge.
        let window = OnboardingWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Metrics.onboardingWidth + Metrics.onboardingShadowMargin * 2,
                height: Metrics.onboardingHeight + Metrics.onboardingShadowMargin * 2
            ),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Carried for assistive technology and the Window menu even though nothing
        // draws it: an untitled window is announced as "window".
        window.title = "Welcome to \(AppInfo.name)"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        // AppKit's shadow is replaced by the one in the chrome — see the note there.
        window.hasShadow = false
        // There is no title bar to grab, so the whole panel is the drag handle.
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.onCancel = { [weak self] in self?.dismiss() }
        window.contentView = NSHostingView(rootView: root)
        window.delegate = self
        window.center()

        self.window = window
        bringToFront(window)
    }

    /// Plays the card out, then closes the window.
    ///
    /// Closing immediately would make Done and Escape feel like the window was shot
    /// rather than dismissed, and the entrance animation would be the only motion the
    /// user ever sees. The close still goes through `close()`, so the teardown in
    /// `windowWillClose` runs whichever route was taken.
    func dismiss() {
        guard let chromeState, !chromeState.isClosing else {
            window?.close()
            return
        }

        withAnimation(.spring(response: OnboardingChromeState.exitDuration, dampingFraction: 1)) {
            chromeState.isClosing = true
        }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(OnboardingChromeState.exitDuration))
            self?.window?.close()
        }
    }

    private func bringToFront(_ window: NSWindow) {
        // Activation policy is owned centrally. Dropping it back to `.accessory` from
        // here used to deactivate the whole app even when the Settings window was still
        // open, which threw focus to whatever app happened to be next in the stack.
        AppActivationManager.shared.present(window)
    }
}

/// Routes Escape to the presenter so it plays the exit animation instead of the window
/// vanishing outright.
///
/// `canBecomeKey`/`canBecomeMain` are overridden defensively: they are already true for
/// a `.titled` window, but every control in this panel stops working if the window ever
/// becomes borderless again, and that failure is silent.
private final class OnboardingWindow: NSWindow {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

extension OnboardingPresenter: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Closing by any route counts as "seen", including the red button — otherwise
        // dismissing the window would re-summon it on every launch.
        preferences?.hasCompletedOnboarding = true
        preferences = nil
        window = nil
        chromeState = nil
        // No policy change here: AppActivationManager sees this window close and only
        // demotes the app once nothing else is on screen.
    }
}

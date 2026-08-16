import AppKit
import os

/// The single owner of WhizMe's activation policy.
///
/// A menu bar utility lives as `.accessory` (no Dock tile, `LSUIElement`), but a real
/// window — Settings, onboarding — needs `.regular` to take keyboard focus and appear
/// in ⌘-Tab. Getting that transition wrong is very visible:
///
/// * Setting `.accessory` while a window is still open **deactivates the app**. macOS
///   then promotes whatever app is next in the stack, so the user's Settings window
///   sinks behind an unrelated app for no reason they can see.
/// * Missing the transition the other way leaves a Dock tile behind after the last
///   window closes.
///
/// Both used to happen because three different places set the policy independently and
/// identified windows by `title` — which changes with the selected Settings tab, so the
/// guards silently stopped matching the moment the user left the General tab.
///
/// Here the policy is a pure function of one thing: how many app windows are open.
@MainActor
final class AppActivationManager {
    static let shared = AppActivationManager()

    /// Windows that justify `.regular`. Identity-keyed — never title-keyed.
    private var trackedWindows: Set<ObjectIdentifier> = []

    /// Open sessions for windows this app cannot track by identity because it never
    /// receives them — Sparkle builds its update alert inside the framework.
    ///
    /// Counted rather than boolean: a scheduled check and a manual "Check Now" can
    /// overlap, and the first one to finish must not demote the app out from under
    /// the second.
    private var externalWindowSessions = 0
    private var closeObserver: NSObjectProtocol?
    private var pendingDemotion: Task<Void, Never>?
    private var promotionWork: Task<Void, Never>?
    private var focusReturnObserver: NSObjectProtocol?

    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "Activation")

    private init() {}

    // MARK: - Window tracking

    /// Registers a window whose presence should keep the app in `.regular`.
    /// Idempotent — SwiftUI hands us the same window on every layout pass.
    func track(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard !trackedWindows.contains(id) else { return }

        trackedWindows.insert(id)
        installCloseObserverIfNeeded()
        syncPolicy()
    }

    /// Brings a tracked window to the front, promoting the app first so it can take
    /// keyboard focus. An `.accessory` app cannot become key on its own.
    func present(_ window: NSWindow) {
        track(window)
        forceActivate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Brings the app forward even when another app currently holds activation.
    ///
    /// `NSApp.activate()` — the macOS 14 replacement — participates in cooperative
    /// activation and *declines* to pull focus away from whatever app is frontmost.
    /// That is the right default for unsolicited activation, but every caller here is
    /// completing a round trip the user started inside our own window: they clicked a
    /// button, got sent to System Settings, and closed it again. Measured with another
    /// app frontmost, `activate()` leaves `NSApp.isActive == false` and the window
    /// stays buried, which is exactly the "Settings disappeared" report.
    private func forceActivate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func untrack(_ id: ObjectIdentifier) {
        guard trackedWindows.remove(id) != nil else { return }
        syncPolicy()
        promoteRemainingWindow()
    }

    /// Hands focus to another of our windows when one closes.
    ///
    /// AppKit does not do this for us here. Closing the walkthrough that was opened on
    /// top of Settings resigns the app's active status, and because the closing window
    /// was the key one, nothing takes its place — the app goes inactive and the still
    /// open Settings window sinks behind whatever is next in the stack. Keeping the
    /// policy at `.regular` was necessary but not sufficient; focus has to be handed on
    /// explicitly.
    private func promoteRemainingWindow() {
        guard !trackedWindows.isEmpty else { return }

        promotionWork?.cancel()
        promotionWork = Task { [weak self] in
            // The closing window is still key while `willClose` is being delivered, so
            // wait for the close to finish before choosing its replacement.
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let self else { return }

            guard let next = NSApp.windows.first(where: {
                self.trackedWindows.contains(ObjectIdentifier($0)) && $0.isVisible
            }) else { return }

            self.forceActivate()
            next.makeKeyAndOrderFront(nil)
            self.promotionWork = nil
        }
    }

    /// One observer for every window, rather than one per window: the notification
    /// already carries the window that is closing.
    private func installCloseObserverIfNeeded() {
        guard closeObserver == nil else { return }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // `Notification` and `NSWindow` are both non-Sendable, so the identity is
            // taken out here — the block already runs on the main queue, and
            // `ObjectIdentifier` is all the actor-isolated side needs.
            guard let window = notification.object as? NSWindow else { return }
            let id = ObjectIdentifier(window)
            MainActor.assumeIsolated {
                self?.untrack(id)
            }
        }
    }

    // MARK: - Policy

    /// Keeps the app in `.regular` until the matching `endExternalWindowSession()`.
    ///
    /// This exists so that policy still has exactly one owner. The alternative —
    /// letting the updater call `NSApp.setActivationPolicy` directly — is the
    /// scattered-ownership bug described at the top of this file, reintroduced.
    func beginExternalWindowSession() {
        externalWindowSessions += 1
        syncPolicy()
        forceActivate()
    }

    func endExternalWindowSession() {
        guard externalWindowSessions > 0 else { return }
        externalWindowSessions -= 1
        syncPolicy()
    }

    /// True while anything at all justifies `.regular`.
    private var needsRegularPolicy: Bool {
        !trackedWindows.isEmpty || externalWindowSessions > 0
    }

    private func syncPolicy() {
        if !needsRegularPolicy {
            scheduleDemotion()
        } else {
            pendingDemotion?.cancel()
            pendingDemotion = nil
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    /// Demotion is deferred by one turn of the run loop.
    ///
    /// `willClose` fires while the window is still on screen and still key. Switching
    /// to `.accessory` at that instant makes macOS resign our active status mid-close,
    /// which is what threw focus to a random app. Waiting until the close has actually
    /// completed lets AppKit hand focus to the right place — and if another window
    /// opened in the meantime (closing onboarding to reveal Settings), the check below
    /// cancels the demotion entirely.
    private func scheduleDemotion() {
        pendingDemotion?.cancel()
        pendingDemotion = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            guard !self.needsRegularPolicy else { return }
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
            self.pendingDemotion = nil
        }
    }

    // MARK: - Returning from System Settings

    /// Arms a one-shot handoff: when System Settings quits, put WhizMe's own window
    /// back in front.
    ///
    /// Deliberately scoped to termination of that one bundle id. Reacting to it merely
    /// *deactivating* would steal focus from whatever app the user chose next, which is
    /// worse than the problem being solved.
    func reclaimFocusWhenSystemSettingsCloses() {
        guard focusReturnObserver == nil else { return }

        focusReturnObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Same reason as above: pull the Sendable bundle id out before the hop.
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                guard bundleID == "com.apple.systempreferences" else { return }

                self.disarmFocusReturn()

                // Only if the user still has one of our windows open — otherwise there
                // is nothing to come back to and we would be barging in.
                guard !self.trackedWindows.isEmpty else { return }
                self.forceActivate()
                NSApp.windows
                    .first { self.trackedWindows.contains(ObjectIdentifier($0)) }?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }

    private func disarmFocusReturn() {
        guard let focusReturnObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(focusReturnObserver)
        self.focusReturnObserver = nil
    }
}

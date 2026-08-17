import AppKit
import SwiftUI

/// Owns the app-wide object graph and the launch/terminate lifecycle.
///
/// `AppEnvironment` lives here rather than in `@State` on the `App` struct so that
/// `applicationDidFinishLaunching` can bootstrap global shortcuts before the user
/// ever opens the menu — a `MenuBarExtra`'s content is not built until it is clicked.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.bootstrap()
        
        setupMenuBar()

        startFirstRunIfNeeded()
    }

    /// The first-launch sequence: welcome, then the home screen, then the permission
    /// walkthrough only if something is actually missing.
    ///
    /// Each step is gated by its own flag. Re-opening the walkthrough on every launch
    /// where a permission is missing would turn a deliberate "skip" into a nag — and on
    /// ad-hoc builds, where macOS drops the grant on each rebuild, it would fire every
    /// single time. The menu bar's warning banner carries the message from there on.
    private func startFirstRunIfNeeded() {
        guard !environment.preferences.hasSeenWelcome else {
            if !environment.preferences.hasCompletedOnboarding {
                OnboardingPresenter.shared.present(environment: environment)
            }
            return
        }

        playWelcome()
    }

    /// Runs the welcome and everything that follows it. Also the entry point for the
    /// replay button in Settings.
    func playWelcome() {
        WelcomeCinematicPresenter.shared.present { [weak self] in
            guard let self else { return }

            // Marked seen on completion rather than on launch: a crash mid-animation
            // should not cost the user the one chance to see it.
            self.environment.preferences.hasSeenWelcome = true

            Task { @MainActor in
                await self.openHomeThenRequestPermissions()
            }
        }
    }

    /// Opens Settings on Home, then asks for any missing permission.
    ///
    /// The permission window is meant to arrive *over* the home page, so the user sees
    /// what they are being asked to unlock. Presenting both in one frame stacks them in
    /// an arbitrary order.
    private func openHomeThenRequestPermissions() async {
        SettingsPresenter.shared.present(environment: environment, section: .home)

        // Let the home page land before anything covers it.
        try? await Task.sleep(for: .seconds(0.65))

        // Re-read instead of trusting the cache. Polling stops once nothing is missing,
        // so a system where everything is already granted would otherwise be asked again
        // on the strength of a stale reading — which is exactly the pointless dialog this
        // check exists to avoid.
        environment.permissions.refresh()
        guard !environment.permissions.allGranted else { return }

        OnboardingPresenter.shared.present(environment: environment)
    }
    
    private func setupMenuBar() {
        // Setup Popover
        popover = NSPopover()
        popover.behavior = .transient
        // Wrap the SwiftUI view in an NSHostingController
        popover.contentViewController = NSHostingController(rootView: MenuBarView().environment(environment))
        
        // Setup Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        observeAwakeState()
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Show standard menu on right click
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))

            // Names the waiting version when there is one, so the menu itself carries
            // the reminder for anyone who dismissed or never saw the banner.
            let updateTitle = environment.updates.availableUpdateVersion
                .map { "Update to \($0)…" } ?? "Check for Updates…"
            let updateItem = NSMenuItem(title: updateTitle, action: #selector(checkForUpdates), keyEquivalent: "")
            updateItem.isEnabled = environment.updates.canCheckForUpdates
            menu.addItem(updateItem)

            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil // reset for next left click
        } else {
            // Left click
            if popover.isShown {
                popover.performClose(sender)
            } else if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Bring app to front so it can receive clicks outside to close transient popover
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    @objc private func checkForUpdates() {
        environment.updates.checkForUpdates()
    }

    @objc private func showSettings() {
        SettingsPresenter.shared.present(environment: environment)
    }
    
    private func observeAwakeState() {
        withObservationTracking {
            let isActive = environment.awake.isActive
            DispatchQueue.main.async { [weak self] in
                self?.statusItem?.button?.contentTintColor = isActive ? .controlAccentColor : nil
            }
        } onChange: {
            DispatchQueue.main.async { [weak self] in
                self?.observeAwakeState()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.shutdown()
    }

    /// Closing the Settings or onboarding window must not quit a menu bar utility.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

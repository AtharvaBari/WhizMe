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

        // First run only. Re-opening this window on every launch where a permission is
        // missing turns a deliberate "skip" into a nag — and on ad-hoc builds, where
        // macOS drops the grant on each rebuild, it would fire every single time. The
        // menu bar's warning banner carries the message from here on.
        if !environment.preferences.hasCompletedOnboarding {
            OnboardingPresenter.shared.present(environment: environment)
        }
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

            let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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

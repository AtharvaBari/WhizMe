import SwiftUI

/// WhizMe is a pure menu bar utility: `LSUIElement` is `YES` in Info.plist, so there is
/// no Dock tile and no main window. The menu bar item is a hand-built `NSStatusItem` in
/// `AppDelegate`, not a `MenuBarExtra`.
///
/// Every window is presented as a plain `NSWindow` — Settings by `SettingsPresenter`,
/// the welcome by `WelcomeCinematicPresenter`, the permission walkthrough by
/// `OnboardingPresenter`. An accessory app has no window to open one *from* at launch,
/// and SwiftUI's scenes need one.
///
/// The `Settings` scene below is vestigial: `App` requires a scene, and this app never
/// realises one, which is precisely why `showSettingsWindow:` silently did nothing and
/// Settings is hosted manually instead. See `SettingsPresenter` for the full account.
@main
struct WhizMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.environment)
        }
    }
}

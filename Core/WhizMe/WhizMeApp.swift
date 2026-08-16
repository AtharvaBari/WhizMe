import SwiftUI

/// WhizMe is a pure menu bar utility: `LSUIElement` is `YES` in Info.plist, so there
/// is no Dock tile and no main window. The only always-present scene is the
/// `MenuBarExtra`; Settings is a standard ⌘, scene, and onboarding is presented as a
/// plain `NSWindow` (see `OnboardingPresenter`) because an accessory app has no
/// window to open one from at launch.
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

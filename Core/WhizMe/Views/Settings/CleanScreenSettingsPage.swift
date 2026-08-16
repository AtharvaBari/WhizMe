import SwiftUI

/// Settings for Clean Screen, plus the button that starts a session.
struct CleanScreenSettingsPage: View {
    @Environment(AppEnvironment.self) private var app

    let onBack: () -> Void

    var body: some View {
        FeatureSettingsScaffold(feature: .cleanScreen, onBack: onBack) {
            SettingsCard(
                title: "Clean",
                footer: "Escape or Return brings the screen back. Every other key is ignored, so wiping across the keyboard cannot set anything off."
            ) {
                SettingsCardRow(
                    symbolName: app.cleanScreen.isCleaning ? "display.trianglebadge.exclamationmark" : "display",
                    title: app.cleanScreen.isCleaning ? "Screen is blacked out" : "Start cleaning",
                    subtitle: app.cleanScreen.isCleaning
                        ? "Press Esc or Return to bring it back"
                        : "Covers every display so you can wipe the glass"
                ) {
                    Button(app.cleanScreen.isCleaning ? "Stop" : "Start") {
                        app.cleanScreen.toggle()
                    }
                    .controlSize(.small)
                                    }
            }

            SafetyNote(
                text: "Clean Screen and Clean Keyboard never run at once. A blacked-out screen that only Escape dismisses, with the keyboard switched off, would be a Mac you could not get out of — so starting either one stops the other."
            )
        }
    }
}

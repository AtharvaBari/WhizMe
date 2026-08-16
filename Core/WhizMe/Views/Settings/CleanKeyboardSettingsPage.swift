import SwiftUI

/// Settings for Clean Keyboard, plus the button that starts a session.
struct CleanKeyboardSettingsPage: View {
    @Environment(AppEnvironment.self) private var app

    let onBack: () -> Void

    private var accessibility: PermissionState {
        app.permissions.state(for: .accessibility)
    }

    var body: some View {
        FeatureSettingsScaffold(feature: .cleanKeyboard, onBack: onBack) {
            SettingsCard(
                title: "Permission",
                footer: "Blocking keys means intercepting them before every other app, which macOS only allows with Accessibility access."
            ) {
                SettingsCardRow(
                    symbolName: SystemPermission.accessibility.symbolName,
                    title: SystemPermission.accessibility.title,
                    subtitle: SystemPermission.accessibility.rationale
                ) {
                    if accessibility.isGranted {
                        PermissionStatusBadge(state: accessibility)
                    } else {
                        Button("Grant") { app.permissions.request(.accessibility) }
                            .controlSize(.small)
                    }
                }
            }

            SettingsCard(
                title: "Clean",
                footer: app.cleanKeyboard.lastError
                    ?? "Every key is ignored while a session runs. Stop it with the trackpad — no key can, by design."
            ) {
                SettingsCardRow(
                    symbolName: app.cleanKeyboard.isCleaning ? "keyboard.badge.ellipsis" : "keyboard",
                    title: app.cleanKeyboard.isCleaning ? "Keyboard is off" : "Start cleaning",
                    subtitle: app.cleanKeyboard.isCleaning
                        ? "Click the button on screen to bring it back"
                        : "Switches the keyboard off so you can wipe it"
                ) {
                    Button(app.cleanKeyboard.isCleaning ? "Stop" : "Start") {
                        app.cleanKeyboard.toggle()
                    }
                    .controlSize(.small)
                                    }
            }

            SafetyNote(
                text: "If WhizMe ever quits or crashes while the keyboard is off, macOS hands it straight back — the block cannot outlive the app."
            )
        }
    }
}

/// A quiet reassurance block for utilities that take something away from the user.
struct SafetyNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .panel(fill: Theme.well)
    }
}

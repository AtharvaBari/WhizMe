import SwiftUI

/// Settings for the Awake utility: how long a session lasts by default, its shortcut,
/// and a live view of the session currently running.
struct AwakeSettingsPage: View {
    @Environment(AppEnvironment.self) private var app

    let onBack: () -> Void

    var body: some View {
        @Bindable var preferences = app.preferences

        FeatureSettingsScaffold(feature: .awake, onBack: onBack) {
            ShortcutSettingsCard(feature: .awake)

            SettingsCard(title: "Duration") {
                SettingsCardRow(
                    symbolName: "timer",
                    title: "Default duration",
                    subtitle: "Used when Awake is switched on from the menu or its shortcut",
                    tint: Theme.accent
                ) {
                    Picker("", selection: $preferences.defaultAwakeDuration) {
                        ForEach(AwakeDuration.allCases) { duration in
                            Text(duration.menuTitle).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }
            }

            SettingsCard(
                title: "Status",
                footer: app.awake.lastError
                    ?? "Awake holds a power assertion so macOS won't idle-sleep. The display can still dim on its own schedule."
            ) {
                SettingsCardRow(
                    symbolName: app.awake.isActive ? "bolt.fill" : "moon.zzz",
                    title: app.awake.isActive ? "Awake is on" : "Awake is off",
                    subtitle: app.awake.isActive
                        ? app.awake.statusDescription
                        : "No power assertion is held right now",
                    tint: Theme.accent
                ) {
                    Button(app.awake.isActive ? "Turn Off" : "Turn On") {
                        if app.awake.isActive {
                            app.awake.deactivate()
                        } else {
                            app.awake.activate(for: preferences.defaultAwakeDuration)
                        }
                    }
                    .controlSize(.small)
                    .disabled(!preferences.isEnabled(.awake))
                }

                SettingsCardDivider()

                // Quick-start row: the durations that are not the default are otherwise
                // only reachable from the menu bar.
                SettingsCardRow(
                    symbolName: "hand.tap",
                    title: "Start a session",
                    subtitle: "Begin a run of a specific length right now",
                    tint: Theme.accent
                ) {
                    Menu("Start…") {
                        ForEach(AwakeDuration.allCases) { duration in
                            Button(duration.menuTitle) {
                                app.awake.activate(for: duration)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!preferences.isEnabled(.awake))
                }
            }
        }
    }
}

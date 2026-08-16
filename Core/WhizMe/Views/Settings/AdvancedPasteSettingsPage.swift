import SwiftUI

/// Settings for Advanced Paste: its shortcut, and the transforms the chooser offers.
struct AdvancedPasteSettingsPage: View {
    @Environment(AppEnvironment.self) private var app

    let onBack: () -> Void

    var body: some View {
        FeatureSettingsScaffold(feature: .advancedPaste, onBack: onBack) {
            ShortcutSettingsCard(feature: .advancedPaste)

            SettingsCard(
                title: "Transforms",
                footer: "Open the chooser, then press its number — or use the arrow keys and Return."
            ) {
                ForEach(Array(PasteFormat.allCases.enumerated()), id: \.element.id) { index, format in
                    if index > 0 { SettingsCardDivider() }

                    SettingsCardRow(
                        symbolName: format.symbolName,
                        title: format.title,
                        subtitle: format.subtitle,
                        tint: Theme.accent
                    ) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
            }

            SettingsCard(title: "Try it") {
                SettingsCardRow(
                    symbolName: "doc.on.clipboard",
                    title: "Open the chooser",
                    subtitle: "Transforms whatever is on the clipboard right now",
                    tint: Theme.accent
                ) {
                    Button("Open…") { app.trigger(.advancedPaste) }
                        .controlSize(.small)
                        .disabled(!app.preferences.isEnabled(.advancedPaste))
                }
            }
        }
    }
}

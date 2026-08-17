import SwiftUI

/// Settings for Clipboard History: its shortcut, what it holds, and how to get rid of it.
///
/// The privacy section is not a footnote here. A feature that records everything the user
/// copies has to say plainly what it does and does not keep, and give them a way to erase
/// it that is one click and not buried.
struct ClipboardHistorySettingsPage: View {
    @Environment(AppEnvironment.self) private var app

    let onBack: () -> Void

    @State private var isConfirmingDelete = false

    private var history: ClipboardHistoryManager { app.clipboardHistory }

    var body: some View {
        FeatureSettingsScaffold(feature: .clipboardHistory, onBack: onBack) {
            ShortcutSettingsCard(feature: .clipboardHistory)

            SettingsCard(
                title: "History",
                footer: "Arrow keys move, Return copies the selected entry, ⌘P pins it, ⌘⌫ deletes it. Pinned entries are never removed by the limit or by Clear."
            ) {
                SettingsCardRow(
                    symbolName: "tray.full",
                    title: "Entries kept",
                    subtitle: "Up to \(ClipboardHistoryManager.unpinnedLimit) unpinned, plus every pin",
                    tint: Theme.accent
                ) {
                    Text("\(history.entries.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }

                SettingsCardDivider()

                SettingsCardRow(
                    symbolName: "pin",
                    title: "Pinned",
                    subtitle: "Kept until you unpin them",
                    tint: Theme.accent
                ) {
                    Text("\(history.entries.filter(\.isPinned).count)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
            }

            SettingsCard(
                title: "Privacy",
                footer: "Stored in Application Support, readable only by your account, and never sent anywhere."
            ) {
                SettingsCardRow(
                    symbolName: "eye.slash",
                    title: "Passwords are not recorded",
                    subtitle: "Copies marked confidential by password managers are skipped, as is anything shaped like a generated secret",
                    tint: Theme.accent
                ) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                SettingsCardDivider()

                SettingsCardRow(
                    symbolName: "photo.badge.exclamationmark",
                    title: "Text only",
                    subtitle: "Images and files are never stored, so screenshots do not pile up on disk",
                    tint: Theme.accent
                ) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                SettingsCardDivider()

                SettingsCardRow(
                    symbolName: "eraser",
                    title: "Clear history",
                    subtitle: "Removes everything except your pins",
                    tint: Theme.accent
                ) {
                    Button("Clear") { history.clearUnpinned() }
                        .controlSize(.small)
                        .disabled(history.entries.allSatisfy(\.isPinned))
                }

                SettingsCardDivider()

                SettingsCardRow(
                    symbolName: "trash",
                    title: "Delete everything",
                    subtitle: "Pins included, and removes the file from disk",
                    tint: Theme.accent
                ) {
                    Button("Delete…", role: .destructive) { isConfirmingDelete = true }
                        .controlSize(.small)
                        .disabled(history.isEmpty)
                }
            }
        }
        // Confirmed, because it takes the pins too and there is no undo.
        .confirmationDialog(
            "Delete the whole clipboard history?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete Everything", role: .destructive) {
                history.deleteEverything()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned entries are deleted too, and the file is removed from disk. This cannot be undone.")
        }
    }
}

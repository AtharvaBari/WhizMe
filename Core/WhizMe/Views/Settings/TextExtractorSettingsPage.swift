import SwiftUI

/// Settings for Text Extractor. The Screen Recording grant lives here rather than only
/// in the walkthrough, because this is the one utility that cannot run without it and
/// this is where someone comes looking when it fails.
struct TextExtractorSettingsPage: View {
    @Environment(AppEnvironment.self) private var app

    let onBack: () -> Void

    private var screenRecording: PermissionState {
        app.permissions.state(for: .screenRecording)
    }

    var body: some View {
        FeatureSettingsScaffold(feature: .textExtractor, onBack: onBack) {
            ShortcutSettingsCard(feature: .textExtractor)

            SettingsCard(
                title: "Permission",
                footer: "macOS only re-reads this grant when the app starts, so WhizMe needs a relaunch after you switch it on."
            ) {
                SettingsCardRow(
                    symbolName: SystemPermission.screenRecording.symbolName,
                    title: SystemPermission.screenRecording.title,
                    subtitle: SystemPermission.screenRecording.rationale,
                    tint: Theme.accent
                ) {
                    if screenRecording.isGranted {
                        PermissionStatusBadge(state: screenRecording)
                    } else {
                        Button("Grant Access") {
                            app.permissions.request(.screenRecording)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            SettingsCard(title: "Try it", footer: app.ocr.lastError) {
                SettingsCardRow(
                    symbolName: "viewfinder",
                    title: "Capture a region",
                    subtitle: "Drag over anything on screen and the text lands on your clipboard",
                    tint: Theme.accent
                ) {
                    Button("Capture…") { app.trigger(.textExtractor) }
                        .controlSize(.small)
                        .disabled(!app.preferences.isEnabled(.textExtractor) || app.ocr.isCapturing)
                }

                if let text = app.ocr.lastText, !text.isEmpty {
                    SettingsCardDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Last extraction")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(text.count) characters")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }

                        ScrollView {
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 96)
                        .padding(10)
                        .background(Theme.well, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Theme.separator)
                        )

                        HStack {
                            Spacer()
                            Button("Copy again") { PasteboardService.copy(text) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

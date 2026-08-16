import SwiftUI

/// Settings for the Color Picker: which notation lands on the clipboard, its shortcut,
/// and the swatches sampled so far.
struct ColorPickerSettingsPage: View {
    @Environment(AppEnvironment.self) private var app

    let onBack: () -> Void

    var body: some View {
        @Bindable var colorPicker = app.colorPicker

        FeatureSettingsScaffold(feature: .colorPicker, onBack: onBack) {
            ShortcutSettingsCard(feature: .colorPicker)

            SettingsCard(
                title: "Format",
                footer: app.colorPicker.lastColor.map {
                    "Your most recent sample copies as \($0.string(for: colorPicker.preferredFormat))"
                }
            ) {
                SettingsCardRow(
                    symbolName: "number",
                    title: "Copy as",
                    subtitle: "The notation written to the clipboard after sampling",
                    tint: Theme.accent
                ) {
                    Picker("", selection: $colorPicker.preferredFormat) {
                        ForEach(ColorFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                }
            }

            SettingsCard(
                title: "Recent colors",
                footer: app.colorPicker.history.isEmpty ? nil : "Click any swatch to copy it again."
            ) {
                if app.colorPicker.history.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                        Text("No colours sampled yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                } else {
                    VStack(spacing: 12) {
                        // Each swatch is its own button: clicking copies that colour
                        // again in the current format, which is the point of a history.
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                            spacing: 10
                        ) {
                            ForEach(app.colorPicker.history) { color in
                                Button {
                                    app.colorPicker.copy(color, as: colorPicker.preferredFormat)
                                } label: {
                                    VStack(spacing: 5) {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                                            .frame(height: 40)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(Theme.separator)
                                            )

                                        Text(color.hex)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("Copy \(color.hex)")
                            }
                        }

                        HStack {
                            Spacer()
                            Button("Clear history") { app.colorPicker.clearHistory() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

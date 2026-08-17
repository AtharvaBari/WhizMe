import AppKit
import SwiftUI

/// The dropdown panel behind the status item. Strictly a presentation layer: every
/// action routes through `AppEnvironment.trigger(_:)` or a manager, so the same code
/// path runs whether the user clicks here or presses a global shortcut.
///
/// Layout rule for this file: the panel owns one horizontal gutter, and *every* child —
/// header, banner, rows, dividers, footer — lives inside it. Nothing sets its own
/// horizontal padding, which is what keeps all the glyphs and titles on one guide.
struct MenuBarView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header

            if !app.outstandingPermissions.isEmpty {
                permissionBanner
                    .padding(.bottom, 4)
            }

            awakeRow
            colorPickerRow
            textExtractorRow
            advancedPasteRow
            clipboardHistoryRow
            batteryRow
            cleanKeyboardRow
            cleanScreenRow

            sectionDivider
            footer
        }
        .padding(.horizontal, Metrics.panelGutter)
        .padding(.vertical, Metrics.panelGutter)
        .frame(width: Metrics.panelWidth)
    }

    // MARK: - Chrome

    /// Aligned to the same glyph column as the rows below, so the wordmark sits
    /// directly above the utility titles.
    private var header: some View {
        HStack(spacing: Metrics.iconGap) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .iconColumn()

            Text(AppInfo.name)
                .font(.system(size: 13, weight: .semibold))

            Text(AppInfo.version)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.rowPadding)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.horizontal, Metrics.rowPadding)
            .padding(.vertical, 5)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Metrics.rowPadding)
            .padding(.bottom, 3)
    }

    // MARK: - Permissions

    private var permissionBanner: some View {
        Button {
            dismissPanel()
            OnboardingPresenter.shared.present(environment: app)
        } label: {
            HStack(spacing: Metrics.iconGap) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .iconColumn()

                VStack(alignment: .leading, spacing: 1) {
                    Text(permissionBannerTitle)
                        .font(.system(size: 12, weight: .medium))
                    Text("Some utilities can't run yet — set up →")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, Metrics.rowPadding)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.rowCorner, style: .continuous))
            .contentShape(.rect(cornerRadius: Metrics.rowCorner))
        }
        .buttonStyle(.plain)
    }

    private var permissionBannerTitle: String {
        let missing = app.outstandingPermissions
        return missing.count == 1
            ? "\(missing[0].title) access needed"
            : "\(missing.count) permissions needed"
    }

    // MARK: - Utility rows

    private var awakeRow: some View {
        MenuActionRow(
            symbolName: WhizFeature.awake.symbolName,
            title: WhizFeature.awake.title,
            detail: app.awake.isActive ? app.awake.statusDescription : nil,
            isEnabled: app.preferences.isEnabled(.awake),
            action: nil
        ) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(AwakeDuration.allCases) { duration in
                        Button(duration.menuTitle) {
                            app.awake.activate(for: duration)
                        }
                    }
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!app.preferences.isEnabled(.awake))

                Toggle("", isOn: Binding(
                    get: { app.awake.isActive },
                    set: { _ in app.trigger(.awake) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(!app.preferences.isEnabled(.awake))
            }
        }
    }

    private var colorPickerRow: some View {
        MenuActionRow(
            symbolName: WhizFeature.colorPicker.symbolName,
            title: WhizFeature.colorPicker.title,
            detail: app.colorPicker.lastColor?.hex,
            isEnabled: app.preferences.isEnabled(.colorPicker),
            action: { run(.colorPicker) }
        ) {
            HStack(spacing: 7) {
                if let color = app.colorPicker.lastColor {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                        .frame(width: 13, height: 13)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(.separator)
                        )
                }
                shortcutLabel(for: .colorPicker)
            }
        }
    }

    private var textExtractorRow: some View {
        MenuActionRow(
            symbolName: WhizFeature.textExtractor.symbolName,
            title: WhizFeature.textExtractor.title,
            detail: app.ocr.lastError,
            isEnabled: app.preferences.isEnabled(.textExtractor),
            action: { run(.textExtractor) }
        ) {
            if app.ocr.isCapturing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                shortcutLabel(for: .textExtractor)
            }
        }
    }

    private var advancedPasteRow: some View {
        MenuActionRow(
            symbolName: WhizFeature.advancedPaste.symbolName,
            title: WhizFeature.advancedPaste.title,
            detail: nil,
            isEnabled: app.preferences.isEnabled(.advancedPaste),
            action: { run(.advancedPaste) }
        ) {
            shortcutLabel(for: .advancedPaste)
        }
    }

    private var clipboardHistoryRow: some View {
        MenuActionRow(
            symbolName: WhizFeature.clipboardHistory.symbolName,
            title: WhizFeature.clipboardHistory.title,
            // The count answers "is there anything in there" without opening the panel.
            // Empty needs no line: the panel says so itself, in more room.
            detail: app.clipboardHistory.isEmpty
                ? nil
                : "\(app.clipboardHistory.entries.count) items",
            isEnabled: app.preferences.isEnabled(.clipboardHistory),
            action: { run(.clipboardHistory) }
        ) {
            shortcutLabel(for: .clipboardHistory)
        }
    }

    /// A readout, so the row *is* the feature — the live summary sits where a shortcut
    /// would, and clicking opens the detail page.
    private var batteryRow: some View {
        MenuActionRow(
            symbolName: WhizFeature.batteryHealth.symbolName,
            title: WhizFeature.batteryHealth.title,
            detail: app.power.summary,
            action: { openSettings(showing: .batteryHealth) }
        ) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var cleanKeyboardRow: some View {
        MenuActionRow(
            symbolName: WhizFeature.cleanKeyboard.symbolName,
            title: WhizFeature.cleanKeyboard.title,
            detail: app.cleanKeyboard.isCleaning ? "Keyboard is off — click the overlay to stop" : nil,
            action: { openSettings(showing: .cleanKeyboard) }
        ) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var cleanScreenRow: some View {
        MenuActionRow(
            symbolName: WhizFeature.cleanScreen.symbolName,
            title: WhizFeature.cleanScreen.title,
            detail: app.cleanScreen.isCleaning ? "Screen is black — press Esc or Return" : nil,
            action: { openSettings(showing: .cleanScreen) }
        ) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

// MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            MenuActionRow(
                symbolName: "gearshape",
                title: "Settings…",
                isSecondary: true
            ) {
                dismissPanel()
                openSettings()
            }

            MenuActionRow(
                symbolName: "power",
                title: "Quit \(AppInfo.name)",
                isSecondary: true
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Fixed-width trailing text so the shortcut column stays flush across rows.
    private func shortcutLabel(for feature: WhizFeature) -> some View {
        Group {
            if let hotKey = app.hotKeys.hotKey(for: feature) {
                Text(hotKey.displayString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Opens Settings on a utility's own page. On-demand utilities are started from
    /// there rather than from this menu, so a stray click can never black the screen or
    /// switch the keyboard off.
    private func openSettings(showing feature: WhizFeature) {
        app.pendingSettingsFeature = feature
        dismissPanel()
        openSettings()
    }

    /// Runs a utility that takes over the screen. The panel has to go away first —
    /// it sits above everything and would otherwise swallow the drag or the sampler.
    private func run(_ feature: WhizFeature) {
        dismissPanel()
        app.trigger(feature)
    }

    private func dismissPanel() {
        NSApp.windows
            .first { $0.isKeyWindow }?
            .close()
    }
}

#Preview {
    MenuBarView()
        .environment(AppEnvironment())
}

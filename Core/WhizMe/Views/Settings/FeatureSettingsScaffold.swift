import SwiftUI

/// Shared chrome for a single utility's settings page: our own back control, a big
/// identity header with the on/off switch, then whatever cards the utility supplies.
///
/// Built from `SettingsCard` rather than `Form`, so a settings page and the tile grid
/// share one visual language instead of the page dropping into AppKit's grouped table.
struct FeatureSettingsScaffold<Content: View>: View {
    @Environment(AppEnvironment.self) private var app

    let feature: WhizFeature
    /// Where Back returns to — the section the user came from.
    var backTitle: String = "Home"
    let onBack: () -> Void
    /// The utility's own cards.
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBackButton(title: backTitle, action: onBack)
                .padding(.horizontal, Theme.margin)
                .padding(.top, Metrics.trafficLightInset)
                .padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionGap) {
                    header
                    content
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, Theme.margin)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title)
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.text)

                Text(feature.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            if !feature.isOnDemand {
                Toggle("", isOn: Binding(
                    get: { app.preferences.isEnabled(feature) },
                    set: { app.preferences.setEnabled($0, for: feature) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
        }
    }
}

/// The shortcut card every utility page carries, so the control and its explanation are
/// written once.
struct ShortcutSettingsCard: View {
    @Environment(AppEnvironment.self) private var app

    let feature: WhizFeature

    var body: some View {
        SettingsCard(
            title: "Shortcut",
            footer: app.hotKeys.conflicts.contains(feature)
                ? "This combination could not be registered — another app already owns it. Pick a different one."
                : "Click the field and press any combination. Escape cancels, Delete clears."
        ) {
            SettingsCardRow(
                symbolName: "command",
                title: "Global shortcut",
                subtitle: "Works from any app, even when WhizMe is in the background",
                tint: Theme.accent
            ) {
                HStack(spacing: 8) {
                    if app.hotKeys.conflicts.contains(feature) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    ShortcutRecorder(current: app.hotKeys.hotKey(for: feature)) { hotKey in
                        app.hotKeys.rebind(feature, to: hotKey)
                    }
                }
            }
        }
    }
}

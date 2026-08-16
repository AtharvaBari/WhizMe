import SwiftUI

/// One sidebar category: the utilities in that group.
///
/// Same rows as Home so a utility looks identical wherever it is found; only the
/// heading and the membership change.
struct CategoryView: View {
    @Environment(AppEnvironment.self) private var app

    let category: FeatureCategory
    /// Opens a utility's settings page.
    let open: (WhizFeature) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                header

                VStack(spacing: 0) {
                    ForEach(Array(category.features.enumerated()), id: \.element) { index, feature in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }

                        FeatureRow(
                            feature: feature,
                            status: status(for: feature),
                            isHighlighted: isHighlighted(feature),
                            isOn: binding(for: feature),
                            open: { open(feature) }
                        )
                    }
                }
                .panel()
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, Metrics.trafficLightInset + 4)
            .padding(.bottom, Theme.margin)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(category.title)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Theme.text)

            Text(category.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Live state

    private func binding(for feature: WhizFeature) -> Binding<Bool> {
        Binding(
            get: { app.preferences.isEnabled(feature) },
            set: { app.preferences.setEnabled($0, for: feature) }
        )
    }

    private func shortcut(_ feature: WhizFeature) -> String {
        app.hotKeys.hotKey(for: feature)?.displayString ?? "—"
    }

    private func status(for feature: WhizFeature) -> String {
        guard feature.availability == .shipping else { return "Not yet available" }

        switch feature {
        case .awake:
            return app.awake.isActive ? app.awake.statusDescription : shortcut(.awake)
        case .colorPicker:
            if let last = app.colorPicker.lastColor { return last.hex }
            return shortcut(.colorPicker)
        case .textExtractor:
            return app.permissions.state(for: .screenRecording).isGranted
                ? shortcut(.textExtractor)
                : "Needs Screen Recording"
        // On-demand utilities have no shortcut to report, so the status says whether
        // they can run instead.
        case .cleanKeyboard:
            if app.cleanKeyboard.isCleaning { return "Keyboard off" }
            return app.permissions.state(for: .accessibility).isGranted
                ? "Ready"
                : "Needs Accessibility"
        case .cleanScreen:
            return app.cleanScreen.isCleaning ? "Screen blacked out" : "Ready"
        default:
            return shortcut(feature)
        }
    }

    private func isHighlighted(_ feature: WhizFeature) -> Bool {
        switch feature {
        case .awake: app.awake.isActive
        case .textExtractor: !app.permissions.state(for: .screenRecording).isGranted
        case .cleanKeyboard: app.cleanKeyboard.isCleaning || !app.permissions.state(for: .accessibility).isGranted
        case .cleanScreen: app.cleanScreen.isCleaning
        default: false
        }
    }
}

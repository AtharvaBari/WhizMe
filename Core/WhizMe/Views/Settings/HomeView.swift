import SwiftUI

/// The landing page: every utility in one list, most recently added first.
///
/// Ordering is chronological rather than alphabetical or grouped, so what is new is
/// the first thing seen — someone returning after an update finds the addition at the
/// top rather than hunting for it. Grouping is what the sidebar categories are for.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var app

    /// Opens a utility's settings page.
    let open: (WhizFeature) -> Void

    private var released: [WhizFeature] { WhizFeature.releasedNewestFirst }
    private var upcoming: [WhizFeature] { WhizFeature.upcomingNewestFirst }
    /// The most recent addition, badged at the top of the list.
    private var newest: WhizFeature? { released.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                header

                list(released)

                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Coming soon")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(0.6)
                            .foregroundStyle(Theme.textTertiary)

                        list(upcoming)
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, Metrics.trafficLightInset + 4)
            .padding(.bottom, Theme.margin)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func list(_ features: [WhizFeature]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.element) { index, feature in
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
                    isNew: feature == newest,
                    isOn: binding(for: feature),
                    open: { open(feature) }
                )
            }
        }
        .panel()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Home")
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Theme.text)

            Text("Everything WhizMe can do, newest first.")
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
        // On-demand utilities have no shortcut to report. Idle is the common case for
        // both, so it says nothing rather than filling the row with "Ready" — the
        // chevron already says a page is there to open. A blocker still needs saying.
        case .cleanKeyboard:
            if app.cleanKeyboard.isCleaning { return "Keyboard off" }
            return app.permissions.state(for: .accessibility).isGranted
                ? ""
                : "Needs Accessibility"
        case .cleanScreen:
            return app.cleanScreen.isCleaning ? "Screen blacked out" : ""
        // A readout, not a shortcut-driven utility — falling through to `shortcut(_:)`
        // rendered as "—" for a feature that will never have one.
        case .batteryHealth:
            return ""
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

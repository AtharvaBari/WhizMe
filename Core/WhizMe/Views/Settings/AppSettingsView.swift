import SwiftUI

/// The app's own settings, reached from the pinned row at the foot of the sidebar.
///
/// Replaces the old Info page. Info was read-only — a version number and three links —
/// which is a thin reason to occupy the one permanent slot in the sidebar. This keeps
/// that content and puts the things people actually come looking for above it:
/// appearance, what happens at startup, and which privacy grants are held.
struct AppSettingsView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        @Bindable var preferences = app.preferences

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                header

                group("Appearance") {
                    SettingsCardRow(
                        symbolName: preferences.theme.symbolName,
                        title: "Theme",
                        subtitle: "Applies to WhizMe's own windows"
                    ) {
                        Picker("", selection: $preferences.theme) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.title).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }

                group("Startup") {
                    SettingsCardRow(
                        symbolName: "power",
                        title: "Launch at login",
                        subtitle: "Start \(AppInfo.name) automatically in the menu bar"
                    ) {
                        Toggle("", isOn: $preferences.launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }

                    SettingsCardDivider()

                    SettingsCardRow(
                        symbolName: "sparkles",
                        title: "Setup walkthrough",
                        subtitle: "Run the first-launch permission guide again"
                    ) {
                        Button("Show…") {
                            OnboardingPresenter.shared.present(environment: app)
                        }
                        .controlSize(.small)
                    }
                }

                group("Updates") {
                    SettingsCardRow(
                        symbolName: "arrow.triangle.2.circlepath",
                        title: "Check automatically",
                        subtitle: "Looks for a new version once a day"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { app.updates.automaticallyChecksForUpdates },
                            set: { app.updates.automaticallyChecksForUpdates = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }

                    SettingsCardDivider()

                    SettingsCardRow(
                        symbolName: "shippingbox",
                        title: "Current version",
                        subtitle: lastCheckedDescription
                    ) {
                        Button("Check Now") { app.updates.checkForUpdates() }
                            .controlSize(.small)
                            .disabled(!app.updates.canCheckForUpdates)
                    }
                }

                group("Privacy access") {
                    ForEach(Array(SystemPermission.allCases.enumerated()), id: \.element) { index, permission in
                        if index > 0 { SettingsCardDivider() }

                        SettingsCardRow(
                            symbolName: permission.symbolName,
                            title: permission.title,
                            subtitle: permission.rationale
                        ) {
                            let state = app.permissions.state(for: permission)
                            if state.isGranted {
                                PermissionStatusBadge(state: state)
                            } else {
                                Button("Grant") { app.permissions.request(permission) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                about
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, Metrics.trafficLightInset + 4)
            .padding(.bottom, Theme.margin)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { app.permissions.refresh() }
    }

    /// Pairs the running version with when it was last checked, so the row answers
    /// "am I current?" rather than only "what am I running?".
    private var lastCheckedDescription: String {
        guard let date = app.updates.lastUpdateCheckDate else {
            return "\(AppInfo.versionDescription) · never checked"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: date, relativeTo: .now)
        return "\(AppInfo.versionDescription) · checked \(relative)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Settings")
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Theme.text)

            Text("How \(AppInfo.name) looks, starts, and what it's allowed to see.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 0) { content() }
                .panel()
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 14) {
                HStack(spacing: 13) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppInfo.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("\(AppInfo.versionDescription) · MIT Licensed · Zero telemetry")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer(minLength: 12)
                }

                HStack(spacing: 8) {
                    link("GitHub", url: AppInfo.repositoryURL)
                    link("Report an issue", url: AppInfo.issuesURL)
                    link("Discussions", url: AppInfo.discussionsURL)
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .panel()
        }
    }

    private func link(_ title: String, url: URL) -> some View {
        Link(destination: url) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.selection))
        }
        .buttonStyle(.plain)
    }
}

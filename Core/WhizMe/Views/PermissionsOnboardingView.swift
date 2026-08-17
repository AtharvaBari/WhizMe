import AppKit
import SwiftUI

/// First-run walkthrough that explains, in plain language, why WhizMe needs each
/// macOS privacy permission and lets the user grant them one at a time.
///
/// Opens straight onto the permission list. The logo animation belongs to the
/// full-screen welcome (`WelcomeCinematicView`) — having it here too meant the user was
/// greeted twice by the same flourish.
///
/// The list itself is purely presentational: every status it shows comes from
/// `PermissionManager`, which keeps polling in the background, so the badges flip to
/// "Granted" on their own while this window sits next to System Settings.
struct PermissionsOnboardingView: View {
    @Environment(AppEnvironment.self) private var app
    // Not `\.dismiss`: this view is hosted in a plain `NSWindow`, where SwiftUI's
    // dismiss action has no scene to act on and silently does nothing.
    @Environment(\.dismissOnboarding) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The permission list has been asked to come in. Each row reads this with its own
    /// delay, so one flag drives the whole staircase.
    @State private var listRevealed = false

    var body: some View {
        permissionsContent
            .frame(width: Metrics.onboardingWidth)
            .frame(maxHeight: .infinity)
            // Opaque, not a material: the permission cards below use
            // `controlBackgroundColor`, which reads as muddy over a blurred desktop.
            .background(Color(nsColor: .windowBackgroundColor))
            .task {
                // A beat before the rows arrive, so they follow the window's own
                // entrance rather than racing it.
                if !reduceMotion {
                    try? await Task.sleep(for: .seconds(0.12))
                }
                listRevealed = true
            }
    }

    private var permissionsContent: some View {
        VStack(spacing: 0) {
            header
                .rises(listRevealed, step: 0, reduceMotion: reduceMotion)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    if CodeSigningService.isAdHocSigned {
                        AdHocSigningWarning()
                            .rises(listRevealed, step: 1, reduceMotion: reduceMotion)
                    }
                    // Enumerated for the step index: the stagger is what turns four
                    // separate fades into one movement travelling down the list.
                    ForEach(Array(SystemPermission.allCases.enumerated()), id: \.element) { index, permission in
                        PermissionCard(permission: permission)
                            .rises(listRevealed, step: index + 2, reduceMotion: reduceMotion)
                    }
                }
                .padding(Metrics.windowInset)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer
                .rises(listRevealed, step: SystemPermission.allCases.count + 2, reduceMotion: reduceMotion)
        }
    }

    // Gaps deliberately unequal: the logo owns the block, so it gets more air above the
    // title than the title gets above its own supporting line.
    private var header: some View {
        VStack(spacing: 0) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 9, y: 4)

            Text("Welcome to \(AppInfo.name)")
                .font(.system(size: 21, weight: .semibold))
                .tracking(-0.2)
                .padding(.top, 16)

            Text("A couple of privacy settings unlock the utilities below. Grant what you want — you can skip the rest and change your mind in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 44)
        .padding(.top, 30)
        .padding(.bottom, 24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Skip for now") { finish() }
                .buttonStyle(.link)

            Spacer(minLength: 8)

            if !app.permissions.allGranted {
                Text("\(app.permissions.missing.count) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Done") { finish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Metrics.windowInset)
        .padding(.vertical, 14)
    }

    /// Onboarding counts as seen either way — a user who skipped should not be shown
    /// this window again on every launch; Settings keeps the same controls.
    private func finish() {
        app.preferences.hasCompletedOnboarding = true
        dismiss()
    }
}

private extension View {
    /// Rises into place on a per-row delay, turning a list of separate fades into one
    /// movement that travels down the panel.
    ///
    /// - Parameters:
    ///   - revealed: the single flag every row watches.
    ///   - step: position in the staircase. 45ms apart — close enough to read as one
    ///     gesture, far enough apart to be visible. Much more and the last row keeps the
    ///     user waiting for a button they can already see.
    ///   - reduceMotion: when set, everything arrives at once with no offset.
    func rises(_ revealed: Bool, step: Int, reduceMotion: Bool) -> some View {
        let delay = reduceMotion ? 0 : Double(step) * 0.045
        return self
            .offset(y: revealed || reduceMotion ? 0 : 12)
            .opacity(revealed || reduceMotion ? 1 : 0)
            // Critically damped: these rows were not thrown by anyone, so they should
            // settle rather than bounce.
            .animation(.spring(response: 0.42, dampingFraction: 1).delay(delay), value: revealed)
    }
}

/// Shown only on ad-hoc signed builds, where macOS discards the app's privacy grants
/// on every rebuild. Without this the developer sees a permission that is switched on
/// in System Settings and still refused by the app, with nothing explaining why.
private struct AdHocSigningWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "signature")
                .font(.system(size: 16))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: Metrics.largeIconColumn, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text("This build is ad-hoc signed")
                    .font(.system(size: 13, weight: .semibold))

                Text("macOS ties these permissions to the exact binary, so every rebuild revokes them — System Settings will still show the old build as allowed. Run Scripts/setup-signing.sh once to give WhizMe a stable identity.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25))
        )
    }
}

/// One permission: what it is, why it matters, what it unlocks, and its live status.
private struct PermissionCard: View {
    @Environment(AppEnvironment.self) private var app

    let permission: SystemPermission

    /// Set when the permission flips to granted *while this window is open* and the
    /// grant cannot take effect until the process restarts.
    @State private var needsRelaunch = false

    private var state: PermissionState {
        app.permissions.state(for: permission)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: permission.symbolName)
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    // Matching the title's line height keeps the glyph optically on the
                    // title's centre instead of floating above it.
                    .frame(width: Metrics.largeIconColumn, height: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(permission.title)
                        .font(.system(size: 13, weight: .semibold))

                    Text(permission.rationale)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let unlocked = unlockedFeatures {
                        Text("Unlocks \(unlocked)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 12)

                // A single trailing control, top-aligned with the title. The old layout
                // put a status pill beside the title *and* a button on the right, so no
                // two cards agreed on where the right-hand column started.
                action
                    .frame(height: 18)
            }

            if needsRelaunch {
                relaunchNote
            }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .strokeBorder(.quaternary)
        )
        .onChange(of: state) { previous, current in
            guard permission.requiresRelaunch else { return }
            needsRelaunch = !previous.isGranted && current.isGranted
        }
    }

    @ViewBuilder
    private var action: some View {
        if state.isGranted {
            PermissionStatusBadge(state: state)
        } else {
            Button("Grant Access") {
                app.permissions.request(permission)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var relaunchNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: Metrics.largeIconColumn, alignment: .center)

            Text("Restart \(AppInfo.name) to finish enabling \(permission.title).")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button("Relaunch", action: relaunch)
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Human-readable list of the utilities this permission switches on.
    private var unlockedFeatures: String? {
        let titles = permission.poweredFeatures.map(\.title)
        guard !titles.isEmpty else { return nil }
        return titles.formatted(.list(type: .and))
    }

    /// Launches a fresh copy before quitting this one, because macOS only re-reads the
    /// Screen Recording grant at process start.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        Task {
            // Quitting first would leave the user with nothing running if the launch
            // fails, so wait for the replacement to be on its way.
            _ = try? await NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL,
                configuration: configuration
            )
            NSApp.terminate(nil)
        }
    }
}

#Preview {
    PermissionsOnboardingView()
        .environment(AppEnvironment())
        .frame(height: Metrics.onboardingHeight)
}

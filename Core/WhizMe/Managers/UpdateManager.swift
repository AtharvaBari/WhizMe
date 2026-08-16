import AppKit
import Observation
import Sparkle
import os

/// Observable state for software updates, and the app's side of Sparkle's UI callbacks.
///
/// Views read this; nothing outside `UpdateService` touches Sparkle itself.
@MainActor
@Observable
final class UpdateManager: NSObject, SPUStandardUserDriverDelegate {
    /// False while a check is in flight — "Check Now" reads this so two checks cannot
    /// be stacked.
    private(set) var canCheckForUpdates = false

    /// Version string of an update Sparkle has found and the user has not acted on,
    /// or nil. Drives the badge in Settings and the menu bar, so the reminder survives
    /// a dismissed banner — a notification the user swipes away must not be the only
    /// way to learn an update exists.
    private(set) var availableUpdateVersion: String?

    /// Stable identifier so a second reminder replaces the first instead of stacking.
    private static let updateNotificationID = "me.whiz.app.update-available"

    /// Mirrors Sparkle's own stored setting rather than shadowing it in
    /// `UserDefaults`. Sparkle persists this itself, and a second copy in
    /// `PreferencesManager` would be one restart away from disagreeing with it.
    var automaticallyChecksForUpdates: Bool {
        get { service?.automaticallyChecksForUpdates ?? false }
        set { service?.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? { service?.lastUpdateCheckDate }

    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "Updates")
    @ObservationIgnored private var service: UpdateService?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    override init() {
        super.init()
        // Two-phase: the service needs `self` as its user-driver delegate, so it
        // cannot be built in a stored-property initialiser.
        let service = UpdateService(userDriverDelegate: self)
        self.service = service
        canCheckObservation = service.observeCanCheckForUpdates { [weak self] value in
            self?.canCheckForUpdates = value
        }
    }

    func checkForUpdates() {
        service?.checkForUpdates()
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Opts into Sparkle's "gentle reminder" contract: instead of Sparkle throwing its
    /// update window in front of whatever the user is doing, it asks first (below) and
    /// lets the app announce the update in a way that suits it.
    ///
    /// A menu bar utility has no business stealing focus for something that can wait.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle handles a *scheduled* update itself only when it proposes to show it in
    /// immediate and utmost focus — roughly, when the app was just launched or the Mac
    /// has been idle. Any other time we take it and post a banner instead.
    ///
    /// Sparkle never calls this for user-initiated checks; it always presents those
    /// itself. That is the behaviour we want: someone who just clicked "Check for
    /// Updates…" is waiting for a window, and answering with a banner would read as
    /// nothing having happened.
    ///
    /// Must have no side effects — the header is explicit about that — so this only
    /// returns a value and leaves the announcing to the method below.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    /// WhizMe is `LSUIElement`, so it normally runs as `.accessory` and its windows
    /// cannot take keyboard focus. Sparkle's update alert is built inside the
    /// framework and never handed to us, so it cannot be tracked by identity the way
    /// Settings and onboarding are — hence the counted session.
    ///
    /// When `handleShowingUpdate` is false we are showing the reminder instead, so
    /// there is no Sparkle window to promote the app for — only a banner to post.
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            self.availableUpdateVersion = version

            guard !handleShowingUpdate else {
                self.log.info("Update \(version, privacy: .public) found; Sparkle is presenting it")
                AppActivationManager.shared.beginExternalWindowSession()
                return
            }

            self.log.info("Update \(version, privacy: .public) found; posting reminder banner")

            NotificationService.shared.post(
                title: "WhizMe \(version) is available",
                body: "Click to install. You are on \(AppInfo.version).",
                identifier: Self.updateNotificationID
            ) { [weak self] in
                // Clicking the banner is the user asking for the update UI, so this
                // re-enters Sparkle as a user-initiated check — which the delegate
                // above always lets Sparkle present.
                self?.checkForUpdates()
            }
        }
    }

    /// The user has engaged with the update — opened the window, or clicked the
    /// banner. Withdraw the reminder so it is not left sitting in Notification Centre
    /// after it has been acted on.
    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            NotificationService.shared.withdraw(identifier: Self.updateNotificationID)
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            NotificationService.shared.withdraw(identifier: Self.updateNotificationID)
            AppActivationManager.shared.endExternalWindowSession()
        }
    }
}

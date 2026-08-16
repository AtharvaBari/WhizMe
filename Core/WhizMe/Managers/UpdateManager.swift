import AppKit
import Observation
import Sparkle

/// Observable state for software updates, and the app's side of Sparkle's UI callbacks.
///
/// Views read this; nothing outside `UpdateService` touches Sparkle itself.
@MainActor
@Observable
final class UpdateManager: NSObject, SPUStandardUserDriverDelegate {
    /// False while a check is in flight — "Check Now" reads this so two checks cannot
    /// be stacked.
    private(set) var canCheckForUpdates = false

    /// Mirrors Sparkle's own stored setting rather than shadowing it in
    /// `UserDefaults`. Sparkle persists this itself, and a second copy in
    /// `PreferencesManager` would be one restart away from disagreeing with it.
    var automaticallyChecksForUpdates: Bool {
        get { service?.automaticallyChecksForUpdates ?? false }
        set { service?.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? { service?.lastUpdateCheckDate }

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

    /// WhizMe is `LSUIElement`, so it normally runs as `.accessory` and its windows
    /// cannot take keyboard focus. Sparkle's update alert is built inside the
    /// framework and never handed to us, so it cannot be tracked by identity the way
    /// Settings and onboarding are — hence the counted session.
    ///
    /// Without this the update window opens behind whatever the user is working in,
    /// which for a scheduled check reads as the app doing nothing at all.
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        MainActor.assumeIsolated {
            AppActivationManager.shared.beginExternalWindowSession()
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            AppActivationManager.shared.endExternalWindowSession()
        }
    }
}

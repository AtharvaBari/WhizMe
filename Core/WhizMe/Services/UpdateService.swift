import AppKit
import Sparkle
import os

/// The only file in WhizMe that imports Sparkle.
///
/// Sparkle is the project's single third-party dependency (see `.cursorrules`). The
/// reason it earns the exception: the alternative is not "use a system framework",
/// because macOS ships no update mechanism outside the App Store — it is writing
/// privileged, self-modifying install code by hand. Sparkle confines that to one
/// audited component behind this wrapper.
///
/// ## Why an updater matters more here than in a notarized app
///
/// WhizMe is Developer ID-less and therefore un-notarized, so a downloaded release
/// costs the user a trip through System Settings → Privacy & Security to launch it.
/// Sparkle swaps the installed bundle in place rather than handing the user a fresh
/// download to open, so that cost is paid once at install instead of once per release.
///
/// ## What keeps an update trustworthy without Apple in the loop
///
/// Two independent checks, neither of which involves notarization:
///
/// 1. **EdDSA.** Every release is signed with a private key held only by the
///    maintainer; Sparkle verifies it against `SUPublicEDKey` in Info.plist and
///    refuses anything that does not match.
/// 2. **Code signing continuity.** Sparkle rejects an update whose code signature
///    does not match the running app's. That is also what protects the app's TCC
///    grants — Screen Recording is tied to the designated requirement, so an update
///    signed by a different certificate would silently lose it.
@MainActor
final class UpdateService {
    private let controller: SPUStandardUpdaterController
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "Updates")

    /// - Parameter userDriverDelegate: receives the "about to show UI" callbacks so a
    ///   menu bar app can promote itself out of `.accessory` first.
    init(userDriverDelegate: SPUStandardUserDriverDelegate?) {
        // `startingUpdater: true` schedules the first check itself. Sparkle only acts
        // on that once the user has answered its permission prompt, so this does not
        // phone home behind their back on first launch.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )
    }

    /// User-initiated check. Always reports its outcome, including "you are up to
    /// date" — unlike the scheduled check, which stays silent when there is nothing.
    func checkForUpdates() {
        log.info("Manual update check requested")
        controller.updater.checkForUpdates()
    }

    /// False while a check is already running; drives the enabled state of any
    /// "Check Now" control so the user cannot stack two checks.
    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }

    /// KVO bridge for `canCheckForUpdates`, which Sparkle exposes only as an
    /// observable property. The token must outlive the call, so the caller stores it.
    func observeCanCheckForUpdates(
        _ onChange: @escaping @MainActor (Bool) -> Void
    ) -> NSKeyValueObservation {
        controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { updater, _ in
            // `SPUUpdater` is main-thread-only by contract — Sparkle's headers declare
            // it `@MainActor`, which is also why the property cannot simply be read
            // out here. It mutates `canCheckForUpdates` from its own main-queue work,
            // so the KVO callback is already on the main thread; the read and the
            // hand-off both happen inside the isolation check.
            MainActor.assumeIsolated { onChange(updater.canCheckForUpdates) }
        }
    }
}

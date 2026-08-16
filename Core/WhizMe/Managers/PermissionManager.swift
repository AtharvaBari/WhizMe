import AppKit
import Observation
import os

/// Observable mirror of the app's TCC status, kept fresh so the UI can react the
/// moment a permission is granted or revoked.
///
/// All syscalls go through `PermissionService`; this type only decides *when* to make
/// them and holds the answers. Teardown is the owner's responsibility — a `@MainActor`
/// class has a nonisolated `deinit` that may not touch `timer`, and `Timer.invalidate()`
/// is only safe on the run loop that scheduled it — so there is no `deinit` cleanup
/// here. `AppEnvironment.shutdown()` calls `stopMonitoring()`.
@MainActor
@Observable
final class PermissionManager {
    /// Last known state of every permission. Only `refresh()` writes to this.
    private(set) var states: [SystemPermission: PermissionState] = [:]

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isMonitoring = false
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    /// Permissions whose system prompt has already been shown at least once.
    @ObservationIgnored private var promptedPermissions: Set<SystemPermission>
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "Permissions")

    /// Fast enough that granting a permission feels instant, cheap enough to be
    /// invisible — and it only ticks while something is still missing.
    private static let pollInterval: TimeInterval = 2

    private static let promptedKey = "promptedPermissions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored = defaults.array(forKey: Self.promptedKey) as? [String] ?? []
        self.promptedPermissions = Set(stored.compactMap(SystemPermission.init(rawValue:)))

        refresh()
    }

    func state(for permission: SystemPermission) -> PermissionState {
        states[permission] ?? .unknown
    }

    var allGranted: Bool {
        SystemPermission.allCases.allSatisfy { state(for: $0).isGranted }
    }

    var missing: [SystemPermission] {
        SystemPermission.allCases.filter { !state(for: $0).isGranted }
    }

    /// Re-reads every permission synchronously and, while monitoring, adjusts the
    /// polling loop to match: run it when something is missing, idle when it is not.
    func refresh() {
        let next = SystemPermission.allCases.reduce(into: [SystemPermission: PermissionState]()) { result, permission in
            result[permission] = PermissionService.state(for: permission)
        }

        // Assigning unconditionally would wake every observer twice a second for no
        // reason, so only publish real transitions.
        if next != states {
            states = next
            let summary = next.map { "\($0.key.rawValue)=\($0.value.rawValue)" }.sorted().joined(separator: " ")
            log.info("Permission states changed: \(summary, privacy: .public)")
        }

        guard isMonitoring else { return }
        if missing.isEmpty {
            stopPolling()
        } else {
            startPolling()
        }
    }

    /// Begins watching for permission changes. Idempotent.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Polling stops once everything is granted, which leaves revocation
        // undetectable. Re-checking whenever the frontmost app changes covers it:
        // revoking happens in System Settings, and the user always switches away
        // afterwards. Both checks are cheap enough to run on an app switch.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        refresh()
    }

    func stopMonitoring() {
        isMonitoring = false
        stopPolling()

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    /// Asks the system for a permission, degrading to the System Settings deep link
    /// when a prompt would no longer appear.
    func request(_ permission: SystemPermission) {
        guard !state(for: permission).isGranted else { return }

        PermissionService.request(permission)

        // macOS shows a TCC prompt at most once per app identity; every later request
        // is a silent no-op. `PermissionState` cannot distinguish "never asked" from
        // "said no", so the ask is remembered here (across launches — a denial from
        // yesterday must not cost the user a dead-end click today) and any repeat
        // lands them in System Settings instead of nowhere.
        if promptedPermissions.contains(permission) {
            openSettings(for: permission)
        } else {
            promptedPermissions.insert(permission)
            defaults.set(promptedPermissions.map(\.rawValue), forKey: Self.promptedKey)
        }

        // The answer arrives out of band, so make sure something is watching for it.
        if isMonitoring {
            startPolling()
        } else {
            startMonitoring()
        }
    }

    func openSettings(for permission: SystemPermission) {
        PermissionService.openSettings(for: permission)
        // Sending the user to another app is a round trip: when they close System
        // Settings, bring our own window back rather than leaving them staring at
        // whatever app macOS promoted in the meantime.
        AppActivationManager.shared.reclaimFocusWhenSystemSettingsCloses()
    }

    // MARK: - Polling

    /// macOS publishes no KVO key, notification, or callback when a TCC grant changes,
    /// so polling is the only way to notice the user flipping the switch in System
    /// Settings while WhizMe sits in the background.
    private func startPolling() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            // Scheduled from the main actor, so this timer is attached to the main run
            // loop and always fires on the main thread; `assumeIsolated` states that
            // for the compiler without paying for an async hop.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}

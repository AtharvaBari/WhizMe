import ServiceManagement
import os

/// Wrapper over `SMAppService.mainApp`, the modern (macOS 13+) replacement for
/// login-item helper bundles.
///
/// Registration legitimately fails for unsigned or quarantined builds, so every
/// call reports success rather than trapping — the UI reflects the real state.
@MainActor
enum LaunchAtLoginService {
    private static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// - Returns: `true` when the resulting state matches `enabled`.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

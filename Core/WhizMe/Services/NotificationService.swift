import UserNotifications
import os

/// Wrapper over `UNUserNotificationCenter` for the short confirmation banners
/// WhizMe posts after a utility runs ("Copied #FF8800", "Copied 42 characters").
///
/// Authorization is requested lazily — the very first time a utility wants to post —
/// so a user who never triggers one is never nagged. Failures are non-fatal by
/// design: a missing banner must never break the utility that asked for it.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let presenter = ForegroundPresenter()
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "Notifications")
    private var authorizationState: AuthorizationState = .unknown

    private enum AuthorizationState {
        case unknown, granted, denied
    }

    private init() {
        center.delegate = presenter
    }

    /// Handlers for banners that do something when clicked, keyed by the request
    /// identifier. Cleared on delivery of the tap, so this cannot grow without bound.
    private var tapHandlers: [String: () -> Void] = [:]

    /// Posts a banner, requesting authorization first if it has not been resolved yet.
    /// Safe to call from anywhere; silently no-ops when the user has said no.
    ///
    /// - Parameters:
    ///   - identifier: reuse a stable one to *replace* an earlier banner rather than
    ///     stacking a second copy — an update reminder should never pile up.
    ///   - onTap: run when the user clicks the banner. Clicking a banner with no
    ///     handler just dismisses it.
    func post(
        title: String,
        body: String,
        identifier: String = UUID().uuidString,
        onTap: (() -> Void)? = nil
    ) {
        if let onTap {
            tapHandlers[identifier] = onTap
        }
        Task { await postAsync(title: title, body: body, identifier: identifier) }
    }

    /// Withdraws a previously posted banner — used when the user has already dealt
    /// with the thing it was reminding them about.
    func withdraw(identifier: String) {
        tapHandlers.removeValue(forKey: identifier)
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    fileprivate func handleTap(identifier: String) {
        tapHandlers.removeValue(forKey: identifier)?()
    }

    private func postAsync(title: String, body: String, identifier: String) async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // deliver immediately
        )

        do {
            try await center.add(request)
        } catch {
            log.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureAuthorized() async -> Bool {
        switch authorizationState {
        case .granted: return true
        case .denied: return false
        case .unknown: break
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationState = .granted
            return true
        case .denied:
            authorizationState = .denied
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert])
                authorizationState = granted ? .granted : .denied
                return granted
            } catch {
                log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                authorizationState = .denied
                return false
            }
        @unknown default:
            authorizationState = .denied
            return false
        }
    }
}

/// WhizMe is usually the frontmost app when a utility finishes, and macOS
/// suppresses banners for the active app unless the delegate asks otherwise.
///
/// `@unchecked Sendable` is safe here because this type holds no state of its own:
/// both callbacks either return a constant or hop straight to the main actor.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await MainActor.run {
            NotificationService.shared.handleTap(identifier: identifier)
        }
    }
}

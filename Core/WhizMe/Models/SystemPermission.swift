import Foundation

/// A macOS privacy (TCC) permission that one or more WhizMe utilities depend on.
///
/// This type is purely descriptive: it knows *what* a permission is and *where* the
/// user grants it. Reading live status and requesting access is the job of
/// `PermissionService`; observing it over time is the job of `PermissionManager`.
enum SystemPermission: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        }
    }

    var symbolName: String {
        switch self {
        case .accessibility: "hand.point.up.left.fill"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }

    /// Plain-language reason shown during onboarding. Never mention API names here.
    var rationale: String {
        switch self {
        case .accessibility:
            "Lets WhizMe move and resize windows for snapping, and send keystrokes for Advanced Paste."
        case .screenRecording:
            "Lets WhizMe read the pixels you select so Text Extractor can turn them into text."
        }
    }

    /// The utilities that stop working without this permission.
    var poweredFeatures: [WhizFeature] {
        WhizFeature.allCases.filter { $0.requiredPermissions.contains(self) }
    }

    /// Deep link into the matching System Settings → Privacy & Security pane.
    var settingsURL: URL {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }

    /// macOS only re-reads the Screen Recording grant at process launch, so the user
    /// has to relaunch WhizMe after toggling it on.
    var requiresRelaunch: Bool {
        switch self {
        case .accessibility: false
        case .screenRecording: true
        }
    }
}

/// Live state of a single `SystemPermission`.
enum PermissionState: String, Sendable {
    /// The permission has been granted and the feature is usable right now.
    case granted
    /// The permission is absent — either never requested or explicitly revoked.
    case denied
    /// Status could not be determined (should be treated as "not usable yet").
    case unknown

    var isGranted: Bool { self == .granted }

    var label: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Not granted"
        case .unknown: "Checking…"
        }
    }

    var symbolName: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .denied: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

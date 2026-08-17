import Foundation
import Observation

/// User-facing preferences that are not owned by a single utility: which utilities
/// are switched on, whether WhizMe starts at login, and whether onboarding has
/// already been completed.
@MainActor
@Observable
final class PreferencesManager {
    /// Utilities the user has switched on. Disabled utilities keep their shortcuts
    /// unregistered and their menu rows inert.
    var enabledFeatures: Set<WhizFeature> {
        didSet { persistEnabledFeatures() }
    }

    /// Mirrors `SMAppService` state; writing it performs the registration.
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            if !LaunchAtLoginService.setEnabled(launchAtLogin) {
                // Registration was refused — snap back so the toggle never lies.
                launchAtLogin = oldValue
            }
        }
    }

    /// The duration Awake will use when toggled via the global hotkey or menu bar item.
    var defaultAwakeDuration: AwakeDuration {
        didSet { defaults.set(defaultAwakeDuration.rawValue, forKey: Keys.defaultAwakeDuration) }
    }

    /// Appearance for WhizMe's own windows.
    var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// Set once the user has seen the permissions walkthrough.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Set once the full-screen welcome has played.
    ///
    /// Deliberately separate from `hasCompletedOnboarding`: the walkthrough is only shown
    /// when a permission is actually missing, so a user who grants everything up front
    /// would never set that flag — and the welcome would replay on every single launch.
    var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Keys.hasSeenWelcome) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let enabledFeatures = "enabledFeatures"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasSeenWelcome = "hasSeenWelcome"
        static let theme = "theme"
        static let defaultAwakeDuration = "defaultAwakeDuration"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.array(forKey: Keys.enabledFeatures) as? [String] {
            self.enabledFeatures = Set(stored.compactMap(WhizFeature.init(rawValue:)))
        } else {
            self.enabledFeatures = Set(WhizFeature.shipping)
        }

        self.theme = defaults.string(forKey: Keys.theme).flatMap(AppTheme.init(rawValue:)) ?? .system
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.hasSeenWelcome = defaults.bool(forKey: Keys.hasSeenWelcome)
        self.launchAtLogin = LaunchAtLoginService.isEnabled

        if let durationRaw = defaults.string(forKey: Keys.defaultAwakeDuration),
           let duration = AwakeDuration(rawValue: durationRaw) {
            self.defaultAwakeDuration = duration
        } else {
            self.defaultAwakeDuration = .indefinite
        }
    }

    func isEnabled(_ feature: WhizFeature) -> Bool {
        // On-demand utilities have no switch, so there is nothing for a stored set to
        // disagree with — and a user upgrading from a build that predates them would
        // otherwise find them permanently off with no control to turn them back on.
        if feature.isOnDemand { return true }
        return enabledFeatures.contains(feature)
    }

    func setEnabled(_ enabled: Bool, for feature: WhizFeature) {
        if enabled {
            enabledFeatures.insert(feature)
        } else {
            enabledFeatures.remove(feature)
        }
    }

    private func persistEnabledFeatures() {
        defaults.set(enabledFeatures.map(\.rawValue), forKey: Keys.enabledFeatures)
    }
}

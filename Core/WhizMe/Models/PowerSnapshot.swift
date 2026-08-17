import Foundation

/// Everything the Battery utility displays, read in one pass.
///
/// One value type rather than a manager full of separate properties: the readings are
/// only meaningful together — a charge percentage without knowing whether it is charging
/// tells the user nothing — and publishing them as a unit means the UI can never render
/// half of an update.
struct PowerSnapshot: Sendable, Equatable {
    /// `nil` on a Mac with no battery. Desktops are not an error case to be reported;
    /// the utility just shows thermal state on its own.
    var battery: Battery?
    var thermal: ThermalState

    static let unavailable = PowerSnapshot(battery: nil, thermal: .unknown)

    struct Battery: Sendable, Equatable {
        /// 0–100, as macOS reports it.
        var chargePercent: Int
        var isCharging: Bool
        var isPluggedIn: Bool

        /// Charge cycles completed. `nil` when the registry does not publish it.
        var cycleCount: Int?

        /// Current full-charge capacity as a percentage of the factory design capacity —
        /// the number System Information calls "Maximum Capacity".
        var healthPercent: Int?

        var temperatureCelsius: Double?

        /// Time until empty, or until full when charging. `nil` while macOS is still
        /// working it out, which it reports for a minute or so after any change.
        var timeRemaining: TimeInterval?

        /// Apple treats 80% design capacity as the service threshold, so that is the line
        /// used here. A hardware fault reported by the registry overrides it.
        var condition: Condition {
            if hasPermanentFailure { return .serviceRecommended }
            guard let healthPercent else { return .unknown }
            return healthPercent >= 80 ? .normal : .serviceRecommended
        }

        var hasPermanentFailure: Bool = false
    }

    enum Condition: Sendable {
        case normal
        case serviceRecommended
        case unknown

        var title: String {
            switch self {
            case .normal: "Normal"
            case .serviceRecommended: "Service Recommended"
            case .unknown: "Unknown"
            }
        }
    }

    /// Mirror of `ProcessInfo.ThermalState`, so the model layer does not hand an AppKit or
    /// Foundation enum straight to the views and lose the chance to name things usefully.
    enum ThermalState: Sendable {
        case nominal
        case fair
        case serious
        case critical
        case unknown

        init(_ state: ProcessInfo.ThermalState) {
            switch state {
            case .nominal: self = .nominal
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            @unknown default: self = .unknown
            }
        }

        var title: String {
            switch self {
            case .nominal: "Normal"
            case .fair: "Warm"
            case .serious: "Hot — being throttled"
            case .critical: "Critical — heavily throttled"
            case .unknown: "Unknown"
            }
        }

        /// What the user can actually do about it, or `nil` when there is nothing to say.
        /// Silence is better than filler on the state that covers most of the time.
        var advice: String? {
            switch self {
            case .nominal: nil
            case .fair: "Fans are working but performance is unaffected."
            case .serious: "macOS is slowing this Mac down to cool it. Closing heavy apps will help."
            case .critical: "macOS is throttling hard to protect the hardware. Stop what is running if you can."
            case .unknown: nil
            }
        }

        /// True once macOS is actually reducing performance, which is the only part most
        /// people care about.
        var isThrottling: Bool {
            self == .serious || self == .critical
        }

        var symbolName: String {
            switch self {
            case .nominal: "thermometer.low"
            case .fair: "thermometer.medium"
            case .serious: "thermometer.high"
            case .critical: "thermometer.sun.fill"
            case .unknown: "thermometer.medium"
            }
        }
    }
}

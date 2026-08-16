import Foundation

/// How long Awake should hold this Mac open for.
///
/// The menu bar submenu and the Settings picker are both generated from
/// `allCases`, so the declaration order below is the order the user sees.
enum AwakeDuration: String, CaseIterable, Identifiable, Sendable {
    case indefinite
    case fiveMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours

    var id: String { rawValue }

    /// Sentence-style label, for buttons and confirmations that stand alone.
    var title: String {
        switch self {
        case .indefinite: "Indefinitely"
        case .fiveMinutes: "For 5 minutes"
        case .thirtyMinutes: "For 30 minutes"
        case .oneHour: "For 1 hour"
        case .twoHours: "For 2 hours"
        case .fourHours: "For 4 hours"
        }
    }

    /// Short label for menus, where the parent row ("Keep Awake") already supplies
    /// the verb and the "for" would just be noise repeated on every line.
    var menuTitle: String {
        switch self {
        case .indefinite: "Indefinitely"
        case .fiveMinutes: "5 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        }
    }

    /// Seconds to hold the assertion for, or `nil` when it never expires on its own.
    var timeInterval: TimeInterval? {
        switch self {
        case .indefinite: nil
        case .fiveMinutes: 5 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .fourHours: 4 * 60 * 60
        }
    }
}

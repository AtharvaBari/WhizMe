import Foundation

/// A reason to keep this Mac awake that ends when the reason does, rather than when a
/// timer runs out.
///
/// The problem with a fixed duration is that the user has to guess. Four hours for a
/// render that finishes in forty minutes leaves the Mac awake for three hours over; one
/// hour for a render that takes ninety minutes fails at exactly the wrong moment. A
/// condition removes the guess.
enum AwakeCondition: Codable, Hashable, Sendable {
    /// Hold while a particular app is running. Identified by bundle id, not name — names
    /// are localised and change between versions.
    case whileAppRuns(bundleID: String, name: String)

    /// Hold while anything is still downloading into the Downloads folder.
    case whileDownloading

    var title: String {
        switch self {
        case .whileAppRuns(_, let name): "While \(name) is running"
        case .whileDownloading: "While downloading"
        }
    }

    var subtitle: String {
        switch self {
        case .whileAppRuns(_, let name):
            "Releases as soon as \(name) quits"
        case .whileDownloading:
            "Watches the Downloads folder for part-finished files"
        }
    }

    var symbolName: String {
        switch self {
        case .whileAppRuns: "app.badge.checkmark"
        case .whileDownloading: "arrow.down.circle"
        }
    }
}

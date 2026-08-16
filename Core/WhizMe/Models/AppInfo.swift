import Foundation

/// Static facts about the running app. Single source of truth for anything that
/// would otherwise be a hardcoded string scattered across services.
enum AppInfo {
    static let name = "WhizMe"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "me.whiz.app"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var versionDescription: String { "Version \(version) (\(build))" }

    static let repositoryURL = URL(string: "https://github.com/AtharvaBari/WhizMe")!
    static let issuesURL = URL(string: "https://github.com/AtharvaBari/WhizMe/issues")!
    static let discussionsURL = URL(string: "https://github.com/AtharvaBari/WhizMe/discussions")!
}

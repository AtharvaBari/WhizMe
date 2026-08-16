import Foundation

/// How the utilities are grouped in the sidebar.
///
/// Grouped by *what the user is trying to do*, not by the framework underneath — the
/// person looking for Text Extractor is thinking "I want something off my screen", not
/// "I want Vision". That is why Color Picker sits with Text Extractor: both sample
/// pixels, even though one ends in a hex string and the other in a paragraph.
enum FeatureCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case screen
    case clipboard
    case windows
    case system
    case cleanMyMac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screen: "Screen"
        case .clipboard: "Clipboard"
        case .windows: "Windows"
        case .system: "System"
        case .cleanMyMac: "CleanMyMac"
        }
    }

    var subtitle: String {
        switch self {
        case .screen: "Pull colours and text off anything you can see"
        case .clipboard: "Reshape what you copy on its way back out"
        case .windows: "Put windows where you want them"
        case .system: "Change how this Mac behaves while you work"
        case .cleanMyMac: "Switch off the keyboard or the screen so you can wipe them"
        }
    }

    var symbolName: String {
        switch self {
        case .screen: "viewfinder"
        case .clipboard: "clipboard"
        case .windows: "macwindow"
        case .system: "gearshape.2"
        case .cleanMyMac: "sparkles"
        }
    }

    /// Utilities in this group: shipping first and newest of those at the top, with
    /// anything unreleased after them.
    var features: [WhizFeature] {
        WhizFeature.releasedNewestFirst.filter { $0.category == self }
            + WhizFeature.upcomingNewestFirst.filter { $0.category == self }
    }

    /// Only groups that actually contain something — an empty category in the sidebar
    /// is a dead end.
    static var populated: [FeatureCategory] {
        allCases.filter { !$0.features.isEmpty }
    }
}

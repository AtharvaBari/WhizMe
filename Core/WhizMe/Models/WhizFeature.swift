import Foundation

/// Every utility WhizMe ships or plans to ship.
///
/// The menu bar and Settings both drive their rows off this enum, so adding a
/// utility means adding a case here plus its manager — never editing view layout.
enum WhizFeature: String, CaseIterable, Identifiable, Codable, Sendable {
    case awake
    case colorPicker
    case textExtractor
    case windowSnapping
    case cropAndLock
    case advancedPaste
    case workspaces
    case cleanKeyboard
    case cleanScreen
    case batteryHealth
    case clipboardHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awake: "Awake"
        case .colorPicker: "Color Picker"
        case .textExtractor: "Text Extractor"
        case .windowSnapping: "Window Snapping"
        case .cropAndLock: "Crop & Lock"
        case .advancedPaste: "Advanced Paste"
        case .workspaces: "Workspaces"
        case .cleanKeyboard: "Clean Keyboard"
        case .cleanScreen: "Clean Screen"
        case .batteryHealth: "Battery & Thermal"
        case .clipboardHistory: "Clipboard History"
        }
    }

    var subtitle: String {
        switch self {
        case .awake: "Keep this Mac from sleeping"
        case .colorPicker: "Sample any pixel on screen"
        case .textExtractor: "Copy text out of anything"
        case .windowSnapping: "Snap windows to zones"
        case .cropAndLock: "Float a live crop of any region"
        case .advancedPaste: "Reformat the clipboard on paste"
        case .workspaces: "Save and restore window layouts"
        case .cleanKeyboard: "Switch the keyboard off so you can wipe it"
        case .cleanScreen: "Black out every display to clean the glass"
        case .batteryHealth: "Cycle count, health, and whether this Mac is throttling"
        case .clipboardHistory: "Search everything you have copied, and pin what you reuse"
        }
    }

    var symbolName: String {
        switch self {
        case .awake: "cup.and.saucer.fill"
        case .colorPicker: "eyedropper.halffull"
        case .textExtractor: "text.viewfinder"
        case .windowSnapping: "rectangle.split.2x2"
        case .cropAndLock: "pip"
        case .advancedPaste: "doc.on.clipboard"
        case .workspaces: "macwindow.on.rectangle"
        case .cleanKeyboard: "keyboard"
        case .cleanScreen: "display"
        case .batteryHealth: "battery.100percent"
        case .clipboardHistory: "list.clipboard"
        }
    }

    /// Which sidebar group this utility belongs to.
    var category: FeatureCategory {
        switch self {
        case .colorPicker, .textExtractor, .cropAndLock: .screen
        case .advancedPaste, .clipboardHistory: .clipboard
        case .windowSnapping, .workspaces: .windows
        case .awake, .batteryHealth: .system
        case .cleanKeyboard, .cleanScreen: .cleanMyMac
        }
    }

    /// The release this utility arrived in, newest first on the Home list.
    ///
    /// An explicit number rather than the enum's declaration order: cases get
    /// reordered for readability, and the day that happens silently the Home page
    /// starts lying about what is new.
    var releaseOrder: Int {
        switch self {
        case .awake: 1
        case .colorPicker: 2
        case .textExtractor: 3
        case .advancedPaste: 4
        case .windowSnapping: 5
        case .cropAndLock: 6
        case .workspaces: 7
        case .cleanScreen: 8
        case .cleanKeyboard: 9
        case .batteryHealth: 10
        case .clipboardHistory: 11
        }
    }

    var requiredPermissions: [SystemPermission] {
        switch self {
        case .awake, .colorPicker, .batteryHealth, .clipboardHistory: []
        case .textExtractor, .cropAndLock: [.screenRecording]
        case .windowSnapping, .workspaces: [.accessibility]
        case .advancedPaste: [.accessibility]
        case .cleanKeyboard: [.accessibility]
        case .cleanScreen: []
        }
    }

    /// Run deliberately from its own settings page: no on/off switch, and no global
    /// shortcut.
    ///
    /// Cleaning the keyboard or the screen is a rare, physical act. A switch would
    /// imply a background helper that is always half-running, and a hotkey that blacks
    /// every display or kills the keyboard is a hotkey nobody wants to hit by accident.
    var isOnDemand: Bool {
        switch self {
        case .cleanKeyboard, .cleanScreen, .batteryHealth: true
        default: false
        }
    }

    var availability: Availability {
        switch self {
        case .awake, .colorPicker, .textExtractor, .advancedPaste, .cleanKeyboard, .cleanScreen, .batteryHealth, .clipboardHistory: .shipping
        case .windowSnapping: .comingSoon
        case .cropAndLock, .workspaces: .pro
        }
    }

    /// Shipping utilities, most recently added first. Drives the Home list.
    ///
    /// Unreleased work is deliberately excluded rather than sorted in: its
    /// `releaseOrder` is the highest, so a plain sort put three things nobody can use
    /// at the top of a list whose whole promise is "here is what is new".
    static var releasedNewestFirst: [WhizFeature] {
        shipping.sorted { $0.releaseOrder > $1.releaseOrder }
    }

    /// Announced but not built, in the order they are planned.
    static var upcomingNewestFirst: [WhizFeature] {
        upcoming.sorted { $0.releaseOrder < $1.releaseOrder }
    }

    /// Utilities the user can actually invoke today.
    static var shipping: [WhizFeature] {
        allCases.filter { $0.availability == .shipping }
    }

    /// Utilities shown in the menu as disabled placeholders.
    static var upcoming: [WhizFeature] {
        allCases.filter { $0.availability != .shipping }
    }

    enum Availability: String, Sendable {
        /// Implemented and shipping in the open-source core.
        case shipping
        /// Free tier, not implemented yet.
        case comingSoon
        /// Planned for the paid Pro tier.
        case pro

        var badge: String? {
            switch self {
            case .shipping: nil
            case .comingSoon: "Soon"
            case .pro: "Pro"
            }
        }
    }
}

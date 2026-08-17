import Foundation

/// A global keyboard shortcut, stored independently of any system framework so the
/// model layer stays free of Carbon/AppKit imports.
///
/// `keyCode` is a virtual key code (the `kVK_ANSI_*` family) — the same numbering
/// `NSEvent.keyCode` and `RegisterEventHotKey` both speak.
struct HotKey: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: Modifiers
    /// What to draw for the key itself, e.g. `"T"` or `"Space"`.
    var keyLabel: String

    /// `⌃⇧⌘T` — matches the order macOS uses in menus.
    var displayString: String { modifiers.symbols + keyLabel }

    struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt32

        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        /// Carbon's `EventHotKeyRef` modifier mask (`controlKey`, `optionKey`,
        /// `shiftKey`, `cmdKey` from `Carbon.HIToolbox`, inlined to keep this file
        /// framework-free).
        var carbonFlags: UInt32 {
            var flags: UInt32 = 0
            if contains(.control) { flags |= 0x1000 }
            if contains(.option) { flags |= 0x0800 }
            if contains(.shift) { flags |= 0x0200 }
            if contains(.command) { flags |= 0x0100 }
            return flags
        }

        var symbols: String {
            var out = ""
            if contains(.control) { out += "⌃" }
            if contains(.option) { out += "⌥" }
            if contains(.shift) { out += "⇧" }
            if contains(.command) { out += "⌘" }
            return out
        }
    }
}

extension HotKey {
    /// Shipping defaults. Chosen to avoid colliding with system and common app
    /// shortcuts by requiring three modifiers.
    static func `default`(for feature: WhizFeature) -> HotKey? {
        switch feature {
        case .textExtractor:
            HotKey(keyCode: 0x11, modifiers: [.control, .shift, .command], keyLabel: "T")
        case .colorPicker:
            HotKey(keyCode: 0x08, modifiers: [.control, .shift, .command], keyLabel: "C")
        case .awake:
            HotKey(keyCode: 0x00, modifiers: [.control, .shift, .command], keyLabel: "A")
        case .advancedPaste:
            HotKey(keyCode: 0x09, modifiers: [.option, .command], keyLabel: "V")
        case .clipboardHistory:
            HotKey(keyCode: 0x09, modifiers: [.control, .shift, .command], keyLabel: "V")
        default:
            nil
        }
    }
}

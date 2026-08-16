import AppKit

/// Thin, testable wrapper over `NSPasteboard.general`.
///
/// Every utility that writes to the clipboard goes through here so there is exactly
/// one place that clears/declares pasteboard types.
@MainActor
enum PasteboardService {
    /// Replaces the general pasteboard contents with `string`.
    /// - Returns: `false` if AppKit refused the write (rare, but never crash on it).
    @discardableResult
    static func copy(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }

    /// Current plain-text contents, if any.
    static var currentString: String? {
        NSPasteboard.general.string(forType: .string)
    }
}

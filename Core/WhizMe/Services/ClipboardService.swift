import AppKit
import CoreGraphics

/// Reads and writes the general pasteboard, and converts what it finds between formats.
///
/// Every transform returns `nil` when it cannot produce a *useful* result, and never
/// quietly substitutes the input. That distinction is what lets `AdvancedPasteManager`
/// offer only the formats that will actually work: the previous version fell back to the
/// untransformed string, so "JSON" on prose pasted the prose unchanged and looked like the
/// feature had silently done nothing.
@MainActor
enum ClipboardService {

    // MARK: - Reading clipboard state

    static var hasImage: Bool {
        NSPasteboard.general.canReadItem(withDataConformingToTypes: [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue,
        ])
    }

    /// True when plain text can actually be produced — which is not the same as "some
    /// text-ish type is on the pasteboard".
    ///
    /// The old check accepted HTML and RTF and then read only `.string`, so a copy from an
    /// app offering rich text without a plain fallback advertised every text transform and
    /// then failed all of them with "Transformation yielded no text".
    static var hasText: Bool { currentPlainText?.isEmpty == false }

    static var currentImage: NSImage? {
        guard let data = NSPasteboard.general.data(forType: .tiff)
            ?? NSPasteboard.general.data(forType: .png) else { return nil }
        return NSImage(data: data)
    }

    /// Plain text from whatever the pasteboard actually holds, cheapest source first: a
    /// real plain string, then RTF, then HTML. Rich sources are flattened through
    /// `NSAttributedString` rather than by stripping tags.
    static var currentPlainText: String? {
        if let string = NSPasteboard.general.string(forType: .string), !string.isEmpty {
            return string
        }
        if let attributed = attributedFromPasteboard() {
            let flattened = attributed.string
            return flattened.isEmpty ? nil : flattened
        }
        return nil
    }

    static var currentString: String? { currentPlainText }

    static var currentHTML: String? { NSPasteboard.general.string(forType: .html) }

    /// True when the pasteboard carries styled text at all, so the flattening and Markdown
    /// transforms are worth offering.
    static var hasRichText: Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.data(forType: .rtf) != nil || pasteboard.data(forType: .html) != nil
    }

    /// Rich text as an attributed string, from RTF or HTML.
    ///
    /// Main-actor bound on purpose: `NSAttributedString`'s HTML importer is backed by
    /// WebKit and is documented main-thread only. That is also why the transforms below are
    /// not pushed onto a background task — the parse has to happen here, and at
    /// clipboard-sized input it costs a few milliseconds, far less than the machinery
    /// needed to do it anywhere else.
    static func attributedFromPasteboard() -> NSAttributedString? {
        let pasteboard = NSPasteboard.general

        // RTF before HTML: it round-trips fonts and links more faithfully, and most apps
        // that put HTML on the pasteboard put RTF beside it.
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return attributed
        }

        if let html = pasteboard.data(forType: .html),
           let attributed = try? NSAttributedString(
               data: html,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ) {
            return attributed
        }

        return nil
    }

    // MARK: - Writing to clipboard

    @discardableResult
    static func copy(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }

    // MARK: - Transformations

    /// Rich text flattened to plain text — "paste without the formatting".
    ///
    /// Offered whenever the clipboard carries styling, **even when the characters are
    /// identical** to the plain string already on it. An earlier version skipped that case
    /// as a no-op, which was wrong and quietly removed the most-wanted transform of the
    /// set: copying from a web page puts matching plain text alongside the HTML, so the row
    /// almost never appeared. The point is not that the text differs — it is that the
    /// destination receives no styling.
    static func plainText() -> String? {
        guard hasRichText, let attributed = attributedFromPasteboard() else { return nil }

        let flattened = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.isEmpty ? nil : flattened
    }

    /// Rich text converted to Markdown by walking the attribute runs.
    ///
    /// Replaces a regex pass over raw HTML. That approach could not see structure: it
    /// matched `<b>` but not a stylesheet, missed anything nested, and turned a page's
    /// `<script>` into pasted JavaScript. Reading the styling the system has already parsed
    /// means bold, italic and links survive from *any* rich source, RTF included, with no
    /// pattern list to keep up to date.
    static func markdown() -> String? {
        guard let attributed = attributedFromPasteboard(), attributed.length > 0 else { return nil }

        var output = ""
        let text = attributed.string as NSString

        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            var fragment = text.substring(with: range)
            guard !fragment.isEmpty else { return }

            // Whitespace-only runs carry no styling worth marking up, and wrapping them
            // produces stray `** **` that breaks every renderer.
            guard !fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                output += fragment
                return
            }

            // Spaces have to sit *outside* the markers: `** bold **` is not emphasis in any
            // Markdown dialect.
            let leading = String(fragment.prefix(while: \.isWhitespace))
            let trailing = String(fragment.reversed().prefix(while: \.isWhitespace).reversed())
            fragment = String(fragment.dropFirst(leading.count).dropLast(trailing.count))

            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.boldFontMask) { fragment = "**\(fragment)**" }
                if traits.contains(.italicFontMask) { fragment = "_\(fragment)_" }
            }

            if let link = attributes[.link] {
                let url = (link as? URL)?.absoluteString ?? String(describing: link)
                fragment = "[\(fragment)](\(url))"
            }

            output += leading + fragment + trailing
        }

        // Rich text uses U+2028/U+2029 for soft and paragraph breaks. Left alone they
        // render as invisible run-together text in every Markdown viewer.
        output = output
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")

        while output.contains("\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Pretty-printed JSON, or `nil` when the text is not JSON.
    ///
    /// `nil` rather than the original string: returning the input is what made the JSON row
    /// appear for every clipboard and do nothing for most of them.
    static func formatJSON(_ text: String?) -> String? {
        guard let text, let data = text.data(using: .utf8) else { return nil }

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            // A bare string or number is technically valid JSON, but pretty-printing it
            // changes nothing — and re-serialising a fragment throws anyway.
            guard object is [Any] || object is [String: Any] else { return nil }

            let pretty = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            return String(data: pretty, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Title Case that leaves acronyms and deliberate casing alone.
    ///
    /// `String.capitalized` lowercases the remainder of every word, so "iPhone SDK" comes
    /// back as "Iphone Sdk" — it mangles exactly the words a user is most likely to care
    /// about. This only raises the first letter, and skips any word that already carries a
    /// capital of its own.
    static func titleCase(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard let first = word.first else { return String(word) }
                let rest = word.dropFirst()
                // "iPhone", "macOS", "NASA" — already deliberately cased.
                if rest.contains(where: \.isUppercase) { return String(word) }
                return first.uppercased() + rest
            }
            .joined(separator: " ")
    }

    // MARK: - Accessibility state

    static var isTextInputFocused: Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard error == .success, let element = focusedElement else { return false }

        // Checked, not forced. `as!` here would terminate the app the first time the
        // accessibility API hands back anything other than an element — and it can: the
        // attribute is documented to return an AXUIElement, but a misbehaving or
        // half-torn-down app is under no obligation to honour that. Losing the paste is
        // acceptable; losing the process is not.
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return false }
        let axElement = element as! AXUIElement

        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role) == .success,
           let roleString = role as? String {
            if roleString == "AXTextField" || roleString == "AXTextArea"
                || roleString == "AXComboBox" || roleString == "AXWebArea" {
                return true
            }
        }

        // Anything exposing a text selection is editable in practice — this is what catches
        // Electron, Chromium, and custom text views.
        var attributes: CFArray?
        if AXUIElementCopyAttributeNames(axElement, &attributes) == .success,
           let names = attributes as? [String] {
            if names.contains(kAXSelectedTextRangeAttribute) || names.contains(kAXSelectedTextAttribute) {
                return true
            }
        }

        return false
    }

    // MARK: - Simulation

    /// Simulates ⌘V into the frontmost app. Requires Accessibility.
    static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 0x09

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

import AppKit
import CoreGraphics

/// Service to handle advanced clipboard operations, including format conversions and active app pasting.
@MainActor
enum ClipboardService {
    
    // MARK: - Reading Clipboard State
    
    static var hasImage: Bool {
        NSPasteboard.general.canReadItem(withDataConformingToTypes: [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue
        ])
    }
    
    static var hasText: Bool {
        NSPasteboard.general.canReadItem(withDataConformingToTypes: [
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.html.rawValue,
            NSPasteboard.PasteboardType.rtf.rawValue
        ])
    }
    
    static var currentImage: NSImage? {
        guard let data = NSPasteboard.general.data(forType: .tiff) ?? NSPasteboard.general.data(forType: .png) else { return nil }
        return NSImage(data: data)
    }
    
    static var currentString: String? {
        NSPasteboard.general.string(forType: .string)
    }
    
    static var currentHTML: String? {
        NSPasteboard.general.string(forType: .html)
    }

    // MARK: - Writing to Clipboard
    
    @discardableResult
    static func copy(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
    
    // MARK: - Transformations
    
    static func convertToMarkdown(from html: String?) -> String? {
        // Very basic HTML to Markdown conversion for demonstration.
        // A complete native HTML to Markdown converter can be complex.
        // As a simple heuristic, we strip tags but preserve links and bold/italics.
        guard let html = html else { return nil }
        
        var markdown = html
        
        // Remove scripts and styles
        // (?s) makes `.` match newlines. Without it a multi-line <script> block survives
        // tag-stripping and its JavaScript ends up pasted as text. `.dotMatchesLineSeparators`
        // is not available here — replacingOccurrences takes String.CompareOptions, which
        // has no such member, so the flag goes in the pattern.
        markdown = markdown.replacingOccurrences(of: "(?s)<script.*?>.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        markdown = markdown.replacingOccurrences(of: "(?s)<style.*?>.*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
        
        // Convert links <a href="URL">TEXT</a> to [TEXT](URL)
        let linkPattern = "<a\\s+(?:[^>]*?\\s+)?href=([\"'])(.*?)\\1[^>]*?>(.*?)</a>"
        markdown = markdown.replacingOccurrences(of: linkPattern, with: "[$3]($2)", options: [.regularExpression, .caseInsensitive])
        
        // Convert headers
        for i in (1...6).reversed() {
            let headerPattern = "<h\(i)[^>]*?>(.*?)</h\(i)>"
            let hashes = String(repeating: "#", count: i)
            markdown = markdown.replacingOccurrences(of: headerPattern, with: "\(hashes) $1\n", options: [.regularExpression, .caseInsensitive])
        }
        
        // Bold
        markdown = markdown.replacingOccurrences(of: "<b[^>]*?>(.*?)</b>", with: "**$1**", options: [.regularExpression, .caseInsensitive])
        markdown = markdown.replacingOccurrences(of: "<strong[^>]*?>(.*?)</strong>", with: "**$1**", options: [.regularExpression, .caseInsensitive])
        
        // Italic
        markdown = markdown.replacingOccurrences(of: "<i[^>]*?>(.*?)</i>", with: "_$1_", options: [.regularExpression, .caseInsensitive])
        markdown = markdown.replacingOccurrences(of: "<em[^>]*?>(.*?)</em>", with: "_$1_", options: [.regularExpression, .caseInsensitive])
        
        // Strip remaining HTML tags
        markdown = markdown.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Clean up entities
        markdown = markdown.replacingOccurrences(of: "&nbsp;", with: " ")
        markdown = markdown.replacingOccurrences(of: "&amp;", with: "&")
        markdown = markdown.replacingOccurrences(of: "&lt;", with: "<")
        markdown = markdown.replacingOccurrences(of: "&gt;", with: ">")
        
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func formatJSON(_ text: String?) -> String? {
        guard let text = text, let data = text.data(using: .utf8) else { return nil }
        
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            return String(data: prettyData, encoding: .utf8)
        } catch {
            // Not a valid JSON, return nil
            return nil
        }
    }
    
    // MARK: - Accessibility State
    
    static var isTextInputFocused: Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard error == .success, let element = focusedElement else { return false }

        // Checked, not forced. `as!` here would terminate the app the first time the
        // accessibility API hands back anything other than an element — and it can:
        // the attribute is documented to return an AXUIElement, but a misbehaving or
        // half-torn-down app is under no obligation to honour that. Losing the paste
        // is acceptable; losing the process is not.
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return false }
        let axElement = element as! AXUIElement

        // Check Role
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role) == .success, let roleString = role as? String {
            if roleString == "AXTextField" || roleString == "AXTextArea" || roleString == "AXComboBox" || roleString == "AXWebArea" {
                return true
            }
        }
        
        // Check for text selection support (Catches Electron/Chromium/Custom text fields)
        var attributes: CFArray?
        if AXUIElementCopyAttributeNames(axElement, &attributes) == .success, let attrArray = attributes as? [String] {
            if attrArray.contains(kAXSelectedTextRangeAttribute) || attrArray.contains(kAXSelectedTextAttribute) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Simulation
    
    /// Simulates Cmd+V to paste the current clipboard content into the frontmost app.
    /// Requires Accessibility permissions.
    static func simulatePaste() {
        // We use CGEvent to simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        
        let vKeyCode: CGKeyCode = 0x09 // 'v'
        
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

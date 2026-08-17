import Foundation

/// One remembered clipboard item.
///
/// Text only, deliberately. Remembering images would mean writing screenshots and copied
/// photos to disk indefinitely — tens of megabytes of the user's private content, kept
/// somewhere they never asked for and would not think to clear. Text is what people
/// actually go back for.
struct ClipboardEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let text: String
    let copiedAt: Date

    /// Bundle id of the app that was frontmost when this was copied, if it could be
    /// determined. Used only to label the row.
    let sourceBundleID: String?
    let sourceName: String?

    /// Pinned entries survive the cap and the "clear" action.
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        text: String,
        copiedAt: Date = .now,
        sourceBundleID: String? = nil,
        sourceName: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.isPinned = isPinned
    }

    /// One line for a row, whitespace collapsed.
    ///
    /// Computed on demand rather than stored: storing it would double what is written to
    /// disk to save work that only the visible rows ever do.
    var preview: String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        let limit = 90
        guard collapsed.count > limit else { return collapsed }
        return collapsed.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "3 lines · 214 characters", for the row's second line.
    var summary: String {
        let lines = text.components(separatedBy: .newlines).count
        let characters = text.count

        let countPart = characters == 1 ? "1 character" : "\(characters) characters"
        return lines > 1 ? "\(lines) lines · \(countPart)" : countPart
    }

    /// True when this looks like something no one wants written to disk.
    ///
    /// A backstop, not the main defence — that is the pasteboard's own concealed marker,
    /// checked in `PasteboardMonitorService`. This catches the case where a password
    /// manager, or an app copying a token, neglects to set it: a single line, no spaces,
    /// long, and mixing character classes the way a generated secret does and prose does
    /// not. Deliberately conservative; a false positive costs one forgotten clipboard item,
    /// a false negative writes someone's password to disk.
    static func looksLikeSecret(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12, trimmed.count <= 128 else { return false }
        guard !trimmed.contains(" "), !trimmed.contains("\n") else { return false }

        // A URL or a file path is long and space-free but is not a secret, and is one of
        // the most common things anyone copies.
        if trimmed.contains("://") || trimmed.hasPrefix("/") { return false }

        let hasLower = trimmed.contains(where: \.isLowercase)
        let hasUpper = trimmed.contains(where: \.isUppercase)
        let hasDigit = trimmed.contains(where: \.isNumber)
        let hasSymbol = trimmed.contains { !$0.isLetter && !$0.isNumber }

        // Three or more classes in one unbroken token is the shape of a generated
        // credential. Ordinary words, identifiers and numbers do not reach it.
        return [hasLower, hasUpper, hasDigit, hasSymbol].filter { $0 }.count >= 3
    }
}

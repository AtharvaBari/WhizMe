import Foundation
import os

/// Loads and saves the clipboard history file.
///
/// ## Where, and why not UserDefaults
///
/// `~/Library/Application Support/me.whiz.app/clipboard-history.json`, with owner-only
/// permissions. UserDefaults would have been less code and the wrong answer: it is cached
/// in memory by `cfprefsd` for the life of the login session, readable by anything running
/// as the user, and awkward to delete on demand — all three are bad properties for a file
/// holding whatever the user has copied today. A plain file can be written `0600` and
/// deleted the instant they ask.
///
/// ## Writes are debounced and atomic
///
/// Saving on every capture would mean a disk write every time anyone copies anything.
/// Instead the manager asks for a save and this coalesces the asks. Each write goes to a
/// temporary file and is swapped into place, so a crash mid-save leaves the previous
/// history intact rather than a truncated file that fails to parse.
@MainActor
final class ClipboardHistoryStore {
    private let fileURL: URL
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "ClipboardHistory")

    private var pendingSave: Task<Void, Never>?

    /// Long enough to absorb a burst of copying, short enough that quitting right after a
    /// copy does not lose it — `flush()` on shutdown covers the rest.
    private static let saveDelay: Duration = .seconds(2)

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = support
            .appendingPathComponent(AppInfo.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("clipboard-history.json")
    }

    func load() -> [ClipboardEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        do {
            return try JSONDecoder().decode([ClipboardEntry].self, from: data)
        } catch {
            // A file that will not parse is worse than no file: it would fail again on every
            // launch. Log it and start clean rather than leaving the feature broken forever.
            log.error("History file unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Requests a save, coalescing rapid calls into one write.
    func scheduleSave(_ entries: [ClipboardEntry]) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.write(entries)
        }
    }

    /// Writes immediately. Called on shutdown, where there is no later.
    func flush(_ entries: [ClipboardEntry]) {
        pendingSave?.cancel()
        pendingSave = nil
        write(entries)
    }

    func deleteFile() {
        pendingSave?.cancel()
        pendingSave = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ entries: [ClipboardEntry]) {
        let directory = fileURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                // Owner-only on the directory as well. A 0600 file inside a world-readable
                // directory still leaks every entry's existence and size.
                attributes: [.posixPermissions: 0o700]
            )

            let data = try JSONEncoder().encode(entries)

            // Atomic: write beside the target, then swap. `.atomic` alone would do it, but
            // the permissions have to be set on the file that ends up in place, and doing
            // both explicitly is what guarantees the history is never briefly world-readable.
            let temporary = directory.appendingPathComponent("clipboard-history.json.tmp")
            try data.write(to: temporary, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        } catch {
            log.error("Could not save history: \(error.localizedDescription, privacy: .public)")
        }
    }
}

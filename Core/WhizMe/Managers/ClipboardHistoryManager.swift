import AppKit
import Observation
import os

/// Observable clipboard history: what was copied, searchable, with pinning.
@MainActor
@Observable
final class ClipboardHistoryManager {
    /// Newest first, pinned entries above the rest.
    private(set) var entries: [ClipboardEntry] = []

    /// The search field's text. Held here rather than in the view so the panel can be
    /// closed and reopened without losing it mid-task.
    var searchText = ""

    /// How many unpinned entries are kept. Past this the oldest fall off.
    ///
    /// 200 is roughly a week of ordinary copying — far enough back to be useful, small
    /// enough that the file stays well under a megabyte and the search stays instant with a
    /// plain linear scan.
    static let unpinnedLimit = 200

    @ObservationIgnored private let store = ClipboardHistoryStore()
    @ObservationIgnored private lazy var monitor = PasteboardMonitorService { [weak self] text, app in
        self?.capture(text, from: app)
    }
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "ClipboardHistory")

    init() {
        entries = store.load()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        monitor.start()
    }

    func stopMonitoring() {
        monitor.stop()
        // Shutdown has no "later", so the debounced save has to be forced now.
        store.flush(entries)
    }

    // MARK: - Search

    /// Entries matching `searchText`, pinned first.
    ///
    /// A linear `localizedCaseInsensitiveContains` over at most a few hundred short strings
    /// — microseconds. An index would be more code and slower to maintain than the scan it
    /// replaced.
    var visibleEntries: [ClipboardEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var isEmpty: Bool { entries.isEmpty }

    // MARK: - Capture

    private func capture(_ text: String, from app: NSRunningApplication?) {
        // Copying the same thing twice moves the existing entry up rather than adding a
        // duplicate — and keeps its pin, which a remove-and-reinsert would silently drop.
        if let index = entries.firstIndex(where: { $0.text == text }) {
            var existing = entries[index]
            existing = ClipboardEntry(
                id: existing.id,
                text: existing.text,
                copiedAt: .now,
                sourceBundleID: existing.sourceBundleID,
                sourceName: existing.sourceName,
                isPinned: existing.isPinned
            )
            entries.remove(at: index)
            insert(existing)
        } else {
            insert(ClipboardEntry(
                text: text,
                sourceBundleID: app?.bundleIdentifier,
                sourceName: app?.localizedName
            ))
        }

        trim()
        store.scheduleSave(entries)
    }

    /// Places an entry in the right half of the list — pinned entries stay above unpinned
    /// ones, and each half stays newest-first.
    private func insert(_ entry: ClipboardEntry) {
        if entry.isPinned {
            entries.insert(entry, at: 0)
        } else {
            let firstUnpinned = entries.firstIndex { !$0.isPinned } ?? entries.count
            entries.insert(entry, at: firstUnpinned)
        }
    }

    /// Drops the oldest unpinned entries past the cap. Pinned entries are never counted or
    /// removed — pinning is the user saying "keep this", and a cap that could evict it would
    /// make the pin a lie.
    private func trim() {
        var unpinnedSeen = 0
        entries = entries.filter { entry in
            guard !entry.isPinned else { return true }
            unpinnedSeen += 1
            return unpinnedSeen <= Self.unpinnedLimit
        }
    }

    // MARK: - Actions

    /// Puts an entry back on the clipboard.
    func copyToClipboard(_ entry: ClipboardEntry) {
        guard ClipboardService.copy(entry.text) else {
            log.error("Pasteboard refused a history entry")
            return
        }
        // Our own write must not come back as a new capture, or using the history would
        // reshuffle it on every use.
        monitor.ignoreCurrentContents()

        // Move it to the top by hand, since the capture path is now suppressed. Using an
        // entry is the same signal as copying it.
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let moved = entries.remove(at: index)
            insert(moved)
            store.scheduleSave(entries)
        }
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()

        // Re-file it: a newly pinned entry belongs above the unpinned ones, and an unpinned
        // one belongs back among them.
        let updated = entries.remove(at: index)
        insert(updated)
        trim()
        store.scheduleSave(entries)
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        store.scheduleSave(entries)
    }

    /// Clears everything except pins.
    func clearUnpinned() {
        entries = entries.filter(\.isPinned)
        store.scheduleSave(entries)
    }

    /// Clears everything and removes the file from disk.
    ///
    /// Separate from `clearUnpinned` and deliberately destructive: someone reaching for this
    /// wants the record gone, not tidied, and leaving a file behind with pinned secrets in
    /// it would not be what they asked for.
    func deleteEverything() {
        entries = []
        searchText = ""
        store.deleteFile()
    }
}

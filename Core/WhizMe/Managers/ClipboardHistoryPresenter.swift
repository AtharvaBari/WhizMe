import AppKit
import SwiftUI

/// Shows the clipboard history panel at the pointer.
///
/// Unlike the Advanced Paste chooser this panel **does** take focus, because it owns a
/// search field and a field nobody can type into is not a search field. That is also why it
/// does not paste for you: taking focus means the app you were typing in is no longer
/// frontmost, so a simulated ⌘V would land in the wrong place. Picking an entry puts it on
/// the clipboard and closes the panel, leaving the paste to you — one keystroke, and it
/// always goes where you are looking.
@MainActor
final class ClipboardHistoryPresenter {
    static let shared = ClipboardHistoryPresenter()

    private var panel: NSPanel?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    var isPresenting: Bool { panel != nil }

    func present(manager: ClipboardHistoryManager) {
        // A second invocation of the shortcut should dismiss, the way every other toggle in
        // the app does, rather than doing nothing while the panel sits there.
        if isPresenting {
            dismiss()
            return
        }

        let root = ClipboardHistoryView(
            manager: manager,
            onPick: { [weak self] entry in
                manager.copyToClipboard(entry)
                self?.dismiss()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.historyPanelWidth, height: Metrics.historyPanelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: root)
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(
            width: Metrics.historyPanelWidth,
            height: Metrics.historyPanelHeight
        ))

        position(panel)
        self.panel = panel

        // An accessory app cannot make a window key without activating, and the search field
        // needs to be typed into.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Clicking away should close it, the way a menu does. Watching for the panel losing
        // key is simpler and more reliable than a global click monitor, which would also have
        // to be torn down and can swallow the click that dismisses.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func dismiss() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil

        panel?.orderOut(nil)
        panel = nil
    }

    /// Centred under the pointer, kept fully on screen.
    private func position(_ panel: NSWindow) {
        let cursor = NSEvent.mouseLocation
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main

        var origin = NSPoint(x: cursor.x - size.width / 2, y: cursor.y - size.height - 12)

        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 {
                // Flip above the pointer rather than clamping to the bottom edge, which
                // would cover what the user is pointing at.
                origin.y = min(cursor.y + 12, visible.maxY - size.height - 8)
            }
        }

        panel.setFrameOrigin(origin)
    }
}

/// Borderless panels refuse key status, which would leave the search field untypeable.
private final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

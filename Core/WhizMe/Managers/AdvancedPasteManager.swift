import AppKit
import Observation
import SwiftUI
import os

/// Drives Advanced Paste: works out what the clipboard can be turned into, shows the
/// chooser, and pastes the result into whatever the user was typing in.
///
/// ## Compute first, then offer
///
/// Every transform runs **once, before the HUD appears**, and a format is listed only if
/// it produced a real result. That is the difference between this and the previous
/// version, which listed a fixed menu and discovered failure after the user had committed
/// to a choice — picking "JSON" on prose pasted the prose unchanged, and picking
/// "Markdown" on plain text did nothing at all.
///
/// It also costs nothing extra: the result is kept, so choosing a row pastes an
/// already-computed string instead of transforming a second time.
///
/// OCR is the one exception. It takes far too long to run before a HUD that is supposed
/// to appear instantly, so an image on the clipboard offers the row on sight and the
/// recognition happens on selection.
@MainActor
@Observable
final class AdvancedPasteManager {
    /// Formats worth showing, each with the text it will paste. Ordered as
    /// `PasteFormat.allCases` is, so the number shortcuts are stable for a given clipboard.
    private(set) var options: [PasteOption] = []
    private(set) var isHUDPresented = false

    @ObservationIgnored private let permissions: PermissionManager
    @ObservationIgnored private var hudWindow: NSPanel?
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "AdvancedPaste")

    /// A format, the text it will paste, and a one-line preview of that text.
    struct PasteOption: Identifiable, Equatable {
        let format: PasteFormat
        /// Already-transformed text, or `nil` for OCR — the only format resolved on demand.
        let result: String?
        /// First line, shortened, for the row subtitle. Empty when there is nothing to show.
        let preview: String

        var id: String { format.rawValue }
    }

    init(permissions: PermissionManager) {
        self.permissions = permissions
    }

    // MARK: - Presenting

    func showHUD() {
        let options = buildOptions()

        guard !options.isEmpty else {
            NotificationService.shared.post(
                title: WhizFeature.advancedPaste.title,
                body: "Nothing on the clipboard can be reformatted."
            )
            return
        }

        self.options = options
        present()
    }

    func hideHUD() {
        hudWindow?.orderOut(nil)
        isHUDPresented = false
    }

    /// Works out every transform the current clipboard supports.
    private func buildOptions() -> [PasteOption] {
        let plain = ClipboardService.currentPlainText
        let hasImage = ClipboardService.hasImage

        return PasteFormat.allCases.compactMap { format in
            switch format {
            case .ocrText:
                // Resolved on selection — see the note in the type comment.
                return hasImage ? PasteOption(format: format, result: nil, preview: "") : nil

            case .plainText:
                return option(format, ClipboardService.plainText())

            case .markdown:
                guard ClipboardService.hasRichText else { return nil }
                return option(format, ClipboardService.markdown())

            case .json:
                return option(format, ClipboardService.formatJSON(plain))

            case .uppercase:
                return option(format, changedCase(of: plain) { $0.localizedUppercase })

            case .lowercase:
                return option(format, changedCase(of: plain) { $0.localizedLowercase })

            case .titleCase:
                return option(format, changedCase(of: plain, using: ClipboardService.titleCase))
            }
        }
    }

    private func option(_ format: PasteFormat, _ result: String?) -> PasteOption? {
        guard let result, !result.isEmpty else { return nil }
        return PasteOption(format: format, result: result, preview: Self.preview(of: result))
    }

    /// A case change is only worth offering when it actually changes something — otherwise
    /// SHOUTED TEXT offers "UPPERCASE" and pastes itself back.
    private func changedCase(of text: String?, using transform: (String) -> String) -> String? {
        guard let text else { return nil }
        let changed = transform(text)
        return changed == text ? nil : changed
    }

    /// One line, collapsed and clipped, so a row can show what it will paste.
    private static func preview(of text: String) -> String {
        let firstLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        let limit = 68
        guard firstLine.count > limit else { return firstLine }
        return firstLine.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func present() {
        if hudWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: 400),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isOpaque = false
            hudWindow = panel
        }

        guard let window = hudWindow else { return }

        window.contentView = NSHostingView(rootView: AdvancedPasteHUDView(manager: self))
        // Size to the content so a two-row list is not a 400pt panel with a void beneath it.
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: Metrics.panelWidth, height: 240))
        positionNearCursor(window)

        // Order front WITHOUT activating. This is the whole point of `.nonactivatingPanel`,
        // and activating here would defeat it: the paste below targets whatever app is
        // frontmost, so stealing focus makes WhizMe the paste target and the user's text
        // lands nowhere. Leaving the original app frontmost is also what lets
        // `isTextInputFocused` read *its* focused element rather than ours.
        window.orderFrontRegardless()
        isHUDPresented = true
    }

    /// Places the panel at the pointer, nudged so it never hangs off a screen edge.
    private func positionNearCursor(_ window: NSWindow) {
        let cursor = NSEvent.mouseLocation
        let size = window.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main

        var origin = NSPoint(x: cursor.x - size.width / 2, y: cursor.y - size.height - 12)

        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            // Flip above the pointer when there is no room below, rather than clamping to
            // the bottom edge and covering what the user is pointing at.
            if origin.y < visible.minY + 8 {
                origin.y = min(cursor.y + 12, visible.maxY - size.height - 8)
            }
        }

        window.setFrameOrigin(origin)
    }

    // MARK: - Pasting

    /// Pastes `option`'s text, running OCR first if that is what was chosen.
    func paste(_ option: PasteOption) {
        hideHUD()

        Task {
            guard let text = await resolve(option) else { return }
            deliver(text)
        }
    }

    /// Returns the text to paste, doing the deferred OCR work when needed.
    private func resolve(_ option: PasteOption) async -> String? {
        if let result = option.result { return result }

        guard option.format == .ocrText, let image = ClipboardService.currentImage else {
            log.error("No result and no image for \(option.format.rawValue, privacy: .public)")
            return nil
        }

        do {
            let text = try await TextRecognitionService.recognizeText(in: image)
            guard !text.isEmpty else {
                NotificationService.shared.post(
                    title: WhizFeature.advancedPaste.title,
                    body: "No text was found in the image on the clipboard."
                )
                return nil
            }
            return text
        } catch {
            log.error("OCR failed: \(error.localizedDescription, privacy: .public)")
            NotificationService.shared.post(
                title: "Advanced Paste failed",
                body: error.localizedDescription
            )
            return nil
        }
    }

    /// Puts `text` on the clipboard and pastes it, or explains why it could not.
    ///
    /// The transformed text is deliberately *left* on the clipboard afterwards. Restoring
    /// the original would mean a second ⌘V pasted something different from the first, which
    /// is worse than losing the original — and the messages below are written on the
    /// assumption that what was asked for is now what is on the clipboard.
    private func deliver(_ text: String) {
        guard ClipboardService.copy(text) else {
            log.error("Pasteboard refused the transformed text")
            NotificationService.shared.post(
                title: "Advanced Paste failed",
                body: "The clipboard refused the transformed text."
            )
            return
        }

        // Re-read rather than trusting the cache, the way every other manager does:
        // polling stops once nothing is missing, so a grant made in System Settings since
        // the last check would otherwise read as denied and silently downgrade to
        // "copied, paste it yourself".
        permissions.refresh()

        guard permissions.state(for: .accessibility).isGranted else {
            NotificationService.shared.post(
                title: "Copied to the clipboard",
                body: "Grant Accessibility access to have WhizMe paste for you."
            )
            return
        }

        guard ClipboardService.isTextInputFocused else {
            NotificationService.shared.post(
                title: "Copied to the clipboard",
                body: "Nothing was focused to paste into, so press ⌘V where you want it."
            )
            return
        }

        Task {
            // The HUD has been ordered out, but the target app does not get focus back
            // within the same run loop turn, and a ⌘V posted before it does goes nowhere.
            try? await Task.sleep(for: .milliseconds(120))
            ClipboardService.simulatePaste()
        }
    }
}

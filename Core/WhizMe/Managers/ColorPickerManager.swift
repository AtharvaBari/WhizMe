import Foundation
import Observation
import os

/// Drives the Color Picker utility: runs the eyedropper, keeps the recent-colors
/// list, and decides what lands on the clipboard.
///
/// `ColorSamplerService` does the AppKit work; this type owns the state and the
/// side effects (clipboard + banner) so the UI can stay a pure projection of it.
@MainActor
@Observable
final class ColorPickerManager {
    /// True while the eyedropper is on screen. Drives the disabled state of the
    /// menu row and stops a second sample from starting.
    private(set) var isSampling = false

    /// Most recent sample. Always identical to `history.first`.
    private(set) var lastColor: SampledColor?

    /// Recent samples, newest first, capped at ``historyLimit``.
    private(set) var history: [SampledColor] = []

    /// Format written to the clipboard when a sample completes. Persisted.
    var preferredFormat: ColorFormat {
        didSet {
            guard preferredFormat != oldValue else { return }
            defaults.set(preferredFormat.rawValue, forKey: Keys.preferredFormat)
        }
    }

    /// Enough to cover a palette a designer is eyeballing without turning the menu
    /// into a scrolling list.
    static let historyLimit = 12

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "ColorPicker")

    private enum Keys {
        static let preferredFormat = "colorPicker.preferredFormat"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // HEX is what the spec promises out of the box, and what most tools expect
        // pasted back in.
        self.preferredFormat = defaults.string(forKey: Keys.preferredFormat)
            .flatMap(ColorFormat.init(rawValue:)) ?? .hex
    }

    /// Shows the eyedropper; on success copies the color and posts a banner.
    func pickColor() {
        // A global shortcut is easy to mash, and a second `show()` while one
        // session is live would strand the first continuation.
        guard !isSampling else { return }
        isSampling = true

        Task {
            let sampled = await ColorSamplerService.sample()
            isSampling = false

            guard let sampled else { return } // Cancelled: no clipboard write, no banner.

            // Copy the recorded entry, not the raw sample: a repeat of the newest
            // color reuses the existing entry, and the two must not disagree.
            copy(record(sampled), as: preferredFormat)
        }
    }

    /// Copies `color` in `format` and confirms it with a banner.
    ///
    /// Also the entry point for "copy this swatch as RGB" from the history list, so
    /// copy-and-confirm has exactly one definition.
    func copy(_ color: SampledColor, as format: ColorFormat) {
        let string = color.string(for: format)

        guard PasteboardService.copy(string) else {
            log.error("Pasteboard refused the color string")
            return
        }

        NotificationService.shared.post(title: "Color copied", body: string)
    }

    func clearHistory() {
        history.removeAll()
        // `lastColor` is the head of the history; leaving it set would keep a swatch
        // on screen for a color the user just asked to forget.
        lastColor = nil
    }

    /// Files a sample at the head of the history.
    /// - Returns: The entry now at `history.first` — the sample itself, or the
    ///   existing entry it duplicated.
    @discardableResult
    private func record(_ color: SampledColor) -> SampledColor {
        // Sampling the same pixel twice in a row is a slip, not a new color — keep
        // the original entry so the list does not fill with copies of one swatch.
        if let newest = history.first, isSameColor(newest, color) {
            lastColor = newest
            return newest
        }

        history.insert(color, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        lastColor = color
        return color
    }

    /// Compares what the user actually sees: two samples that render to the same
    /// 8-bit hex are the same color, whatever the components do in the last decimal.
    private func isSameColor(_ lhs: SampledColor, _ rhs: SampledColor) -> Bool {
        lhs.hex == rhs.hex && abs(lhs.alpha - rhs.alpha) < (1.0 / 255.0)
    }
}

import AppKit
import SwiftUI

/// Click-to-record shortcut field.
///
/// While armed it installs a *local* key monitor, which only sees events destined for
/// this app's key window — so recording cannot swallow keystrokes meant for anything
/// else. The monitor is torn down on the first captured combination, on cancel, and on
/// disappear; leaving one installed would keep eating keys long after the field lost
/// interest in them.
struct ShortcutRecorder: View {
    let current: HotKey?
    /// `nil` clears the binding.
    let onChange: (HotKey?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? cancel() : arm()
            } label: {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                    .frame(minWidth: 96)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.12))
                    )
                    .contentShape(.rect(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            if current != nil && !isRecording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove this shortcut")
            }
        }
        .onDisappear(perform: removeMonitor)
    }

    private var label: String {
        if isRecording { return "Press keys…" }
        return current?.displayString ?? "Click to set"
    }

    private var foreground: Color {
        if isRecording { return .accentColor }
        return current == nil ? .secondary : .primary
    }

    private var background: AnyShapeStyle {
        if isRecording { return AnyShapeStyle(Color.accentColor.opacity(0.12)) }
        return AnyShapeStyle(isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
    }

    // MARK: - Recording

    private func arm() {
        guard monitor == nil else { return }
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape abandons, Delete clears — matching how macOS's own shortcut
            // fields behave, so the interaction needs no explanation.
            if event.keyCode == 53 {
                cancel()
                return nil
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                onChange(nil)
                cancel()
                return nil
            }

            guard let hotKey = Self.hotKey(from: event) else {
                // A bare key with no modifiers would be claimed globally and make the
                // keyboard unusable, so it is refused rather than recorded.
                NSSound.beep()
                return nil
            }

            onChange(hotKey)
            cancel()
            return nil
        }
    }

    private func cancel() {
        isRecording = false
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// Translates a key event into the storable model, or `nil` when the combination
    /// is not usable as a global shortcut.
    static func hotKey(from event: NSEvent) -> HotKey? {
        var modifiers: HotKey.Modifiers = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        // At least one non-shift modifier: Shift+letter is just a capital letter.
        guard !modifiers.isEmpty, modifiers != [.shift] else { return nil }

        return HotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: keyLabel(for: event)
        )
    }

    private static func keyLabel(for event: NSEvent) -> String {
        if let special = specialKeyNames[event.keyCode] { return special }
        // `charactersIgnoringModifiers` gives the key's own legend rather than what the
        // modifiers turned it into (⌥K would otherwise record as "˚").
        if let characters = event.charactersIgnoringModifiers, let first = characters.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private static let specialKeyNames: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

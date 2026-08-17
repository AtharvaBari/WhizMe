import AppKit
import SwiftUI

/// The Advanced Paste chooser: a floating list of clipboard transforms, driven by
/// arrow keys, number keys, or the mouse.
///
/// Same layout system as the menu bar panel — one gutter, one glyph column — so the
/// HUD reads as part of the same app rather than a separate widget.
struct AdvancedPasteHUDView: View {
    var manager: AdvancedPasteManager

    @State private var selectedIndex: Int = 0
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(manager.options.enumerated()), id: \.element.id) { index, option in
                        FormatRow(
                            option: option,
                            shortcutNumber: index + 1,
                            isSelected: selectedIndex == index
                        ) {
                            manager.paste(option)
                        }
                        .onHover { hovering in
                            if hovering { selectedIndex = index }
                        }
                    }
                }
                .padding(Metrics.panelGutter)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: Metrics.panelWidth)
        .frame(maxHeight: 380)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        // Paired with onDisappear: the previous version added a monitor on every
        // appearance and removed none, so after the HUD had been shown three times a
        // single arrow key press moved the selection three rows.
        .onAppear {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKeyDown(event)
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.iconGap) {
            Image(systemName: WhizFeature.advancedPaste.symbolName)
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .iconColumn()

            Text(WhizFeature.advancedPaste.title)
                .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 8)

            Text("↑↓ then ↩")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        // Gutter + row padding, so the header glyph sits on the same column as the
        // rows below it rather than 8pt to their left.
        .padding(.horizontal, Metrics.panelGutter + Metrics.rowPadding)
        .padding(.vertical, 11)
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let count = manager.options.count
        guard count > 0 else { return event }

        switch event.keyCode {
        case 125: // Down arrow
            selectedIndex = (selectedIndex + 1) % count
            return nil
        case 126: // Up arrow
            selectedIndex = (selectedIndex - 1 + count) % count
            return nil
        case 36, 76: // Return / Enter
            manager.paste(manager.options[selectedIndex])
            return nil
        case 53: // Escape
            manager.hideHUD()
            return nil
        default:
            if let characters = event.characters,
               let number = Int(characters),
               number > 0, number <= count {
                manager.paste(manager.options[number - 1])
                return nil
            }
            return event
        }
    }
}

/// One transform. Selection paints the whole row with the accent colour, so every
/// foreground element has to flip together — a badge left in its resting grey against
/// an accent fill was the one piece that looked broken.
private struct FormatRow: View {
    let option: AdvancedPasteManager.PasteOption
    let shortcutNumber: Int

    private var format: PasteFormat { option.format }

    /// The transformed text when there is one, otherwise the format's own description.
    ///
    /// Showing the result is what turns the chooser from a menu of names into something
    /// you can confirm before committing — "Markdown" tells you nothing, the first line of
    /// the Markdown tells you whether the conversion worked.
    private var detail: String {
        option.preview.isEmpty ? format.subtitle : option.preview
    }
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.iconGap) {
                Image(systemName: format.symbolName)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
                    .iconColumn()

                VStack(alignment: .leading, spacing: 1) {
                    Text(format.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))

                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Text("\(shortcutNumber)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(.quaternary))
                    )
            }
            .padding(.horizontal, Metrics.rowPadding)
            .padding(.vertical, Metrics.rowVerticalPadding)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: Metrics.rowCorner, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
            )
            .contentShape(.rect(cornerRadius: Metrics.rowCorner))
        }
        .buttonStyle(.plain)
    }
}

import AppKit
import SwiftUI

/// The clipboard history panel: a search field over a list, driven by the keyboard.
///
/// Same gutter and glyph column as the other panels, so it reads as part of the same app.
struct ClipboardHistoryView: View {
    var manager: ClipboardHistoryManager
    /// Puts the entry on the clipboard and closes the panel.
    let onPick: (ClipboardEntry) -> Void
    let onDismiss: () -> Void

    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    private var rows: [ClipboardEntry] { manager.visibleEntries }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
        }
        .frame(width: Metrics.historyPanelWidth)
        .frame(maxHeight: Metrics.historyPanelHeight)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .onAppear {
            searchFocused = true
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { handleKeyDown($0) }
        }
        .onDisappear {
            // Paired with onAppear. An unremoved monitor accumulates across openings, and
            // then one arrow key moves the selection once per time the panel has been shown.
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        // Typing narrows the list, so the old selection may no longer exist.
        .onChange(of: manager.searchText) { _, _ in selectedIndex = 0 }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: Metrics.iconGap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .iconColumn()

            TextField("Search history", text: Binding(
                get: { manager.searchText },
                set: { manager.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($searchFocused)
            // Return is handled by the key monitor so it picks the selected row rather than
            // submitting an empty search.
            .onSubmit {}

            if !manager.searchText.isEmpty {
                Button {
                    manager.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Metrics.panelGutter + Metrics.rowPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var list: some View {
        if rows.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                            HistoryRow(
                                entry: entry,
                                isSelected: selectedIndex == index,
                                onPick: { onPick(entry) },
                                onTogglePin: { manager.togglePin(entry) },
                                onDelete: { manager.delete(entry) }
                            )
                            .id(entry.id)
                            .onHover { hovering in
                                if hovering { selectedIndex = index }
                            }
                        }
                    }
                    .padding(Metrics.panelGutter)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Keeps a keyboard-driven selection visible; without it arrowing past the
                // fold moves an invisible highlight.
                .onChange(of: selectedIndex) { _, index in
                    guard rows.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(rows[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: manager.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)

            Text(manager.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if manager.isEmpty {
                Text("Anything you copy from now on appears here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let count = rows.count

        switch event.keyCode {
        case 125 where count > 0: // Down
            selectedIndex = (selectedIndex + 1) % count
            return nil
        case 126 where count > 0: // Up
            selectedIndex = (selectedIndex - 1 + count) % count
            return nil
        case 36, 76: // Return / Enter
            guard rows.indices.contains(selectedIndex) else { return nil }
            onPick(rows[selectedIndex])
            return nil
        case 53: // Escape
            onDismiss()
            return nil
        default:
            // ⌘P pins, ⌘⌫ deletes. Plain letters have to reach the search field, so every
            // shortcut here needs a modifier.
            guard event.modifierFlags.contains(.command),
                  rows.indices.contains(selectedIndex) else { return event }

            if event.charactersIgnoringModifiers == "p" {
                manager.togglePin(rows[selectedIndex])
                return nil
            }
            if event.keyCode == 51 { // Delete
                manager.delete(rows[selectedIndex])
                selectedIndex = min(selectedIndex, max(0, rows.count - 2))
                return nil
            }
            return event
        }
    }
}

/// One history entry. Pin and delete appear on the selected row only — showing them on
/// every row turns a readable list into a wall of buttons.
private struct HistoryRow: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    let onPick: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Metrics.iconGap) {
            Image(systemName: entry.isPinned ? "pin.fill" : "doc.on.clipboard")
                .font(.system(size: 12))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconStyle)
                .iconColumn()

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.preview)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))

                Text(metadata)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
            }

            Spacer(minLength: 6)

            if isSelected {
                Button(action: onTogglePin) {
                    Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .help(entry.isPinned ? "Unpin (⌘P)" : "Pin (⌘P)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .help("Delete (⌘⌫)")
            }
        }
        .padding(.horizontal, Metrics.rowPadding)
        .padding(.vertical, Metrics.rowVerticalPadding)
        .frame(minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: Metrics.rowCorner, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
        )
        .contentShape(.rect(cornerRadius: Metrics.rowCorner))
        .onTapGesture(perform: onPick)
    }

    private var iconStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.white) }
        return entry.isPinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
    }

    /// "2 minutes ago · Safari · 214 characters", dropping the parts that are unknown.
    private var metadata: String {
        var parts = [entry.copiedAt.formatted(.relative(presentation: .numeric))]
        if let source = entry.sourceName { parts.append(source) }
        parts.append(entry.summary)
        return parts.joined(separator: " · ")
    }
}

import SwiftUI

/// Our own back control, replacing `NavigationStack`'s toolbar chevron.
///
/// The system button lives in a toolbar, and a toolbar drags the whole stock title bar
/// back with it — the exact chrome this window is trying to shed. Drawn here as a
/// capsule that sits in the content, it also gets to say *where* it goes back to
/// rather than just pointing left.
struct SettingsBackButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .offset(x: isHovering ? -2 : 0)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHovering ? Theme.text : Theme.textSecondary)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .keyboardShortcut("[", modifiers: .command)
    }
}

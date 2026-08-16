import AppKit
import SwiftUI

/// Hands a SwiftUI view the `NSWindow` it is actually hosted in.
///
/// The alternative — listening for `NSWindow` notifications and matching on `title` —
/// breaks as soon as the title changes, which for a Settings window happens every time
/// the user selects a different section.
///
/// Place it in a `.background`, where it takes no space and does not affect layout.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The view is not in a window yet during make; it is by the next run loop turn.
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}

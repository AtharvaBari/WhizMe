import AppKit
import SwiftUI

/// Strips AppKit's stock window chrome so Settings can draw its own.
///
/// Hides the title bar and lets content run to the window's edges, leaving only the
/// traffic lights floating over our layout. Without this the window keeps a titled bar
/// and a toolbar strip above whatever SwiftUI draws, which is the giveaway that a
/// window is "just a Mac app template".
///
/// The traffic lights are deliberately kept: a window the user cannot close is a worse
/// offence than a stock title bar. `Metrics.trafficLightInset` reserves room for them.
struct SettingsWindowStyler: NSViewRepresentable {
    /// Applied to the window itself, so AppKit-drawn parts (traffic lights, native
    /// controls) follow the chosen theme along with the SwiftUI content.
    let theme: AppTheme

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            apply(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            apply(to: window)
        }
    }

    private func apply(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        // A toolbar would re-introduce the strip we just removed. SwiftUI adds one for
        // `navigationTitle`, so it is cleared every time the window is handed back.
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        // Left opaque on purpose. A clear, non-opaque window changes how macOS draws
        // the rounded corners and drop shadow; the surface is painted over this anyway.
        window.backgroundColor = .windowBackgroundColor
        window.appearance = theme.appearance

        AppActivationManager.shared.track(window)
        window.collectionBehavior.insert(.moveToActiveSpace)
    }
}

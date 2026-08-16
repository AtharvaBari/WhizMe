import AppKit
import SwiftUI

/// Puts a SwiftUI view across every display, above everything else.
///
/// Both cleaning utilities need the same thing — a borderless window per screen at
/// screen-saver level — so the window plumbing lives here once rather than being
/// copied into each manager.
@MainActor
final class OverlayPresenter {
    private var windows: [NSWindow] = []

    var isPresenting: Bool { !windows.isEmpty }

    /// - Parameter acceptsKeys: whether the overlay should take keyboard focus. The
    ///   screen blackout needs it (Esc and Return dismiss); the keyboard blocker does
    ///   not, since every key is being swallowed anyway.
    func present<Content: View>(
        acceptsKeys: Bool,
        @ViewBuilder content: () -> Content
    ) {
        guard windows.isEmpty else { return }

        let root = content()

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.canBecomeKeyOverride = acceptsKeys
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = NSHostingView(rootView: AnyView(root))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            windows.append(window)
        }

        if acceptsKeys {
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.makeKey()
        }
    }

    func dismiss() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}

/// Borderless windows refuse key status by default, which would swallow Escape.
private final class OverlayWindow: NSWindow {
    var canBecomeKeyOverride = false

    override var canBecomeKey: Bool { canBecomeKeyOverride }
    override var canBecomeMain: Bool { canBecomeKeyOverride }
}

import AppKit
import SwiftUI

/// Presents the full-screen welcome across every display, and reports when the user is
/// through with it.
///
/// Separate from `OverlayPresenter` — which the cleaning utilities share — for two
/// reasons it cannot express: this is one-shot with a completion callback rather than a
/// toggle, and the displays do not all show the same thing. The animation belongs on one
/// screen; the others get the dim alone, because the same title card repeated across
/// three monitors reads as a rendering fault rather than a flourish.
@MainActor
final class WelcomeCinematicPresenter {
    static let shared = WelcomeCinematicPresenter()

    private var windows: [NSWindow] = []
    private var completion: (() -> Void)?

    private init() {}

    var isPresenting: Bool { !windows.isEmpty }

    /// - Parameter completion: run once, after the overlay has gone, whether the user
    ///   pressed Continue, clicked, or hit Escape.
    func present(completion: @escaping () -> Void) {
        guard windows.isEmpty else { return }

        // No display to draw on — with nothing on screen there is no Continue button to
        // press, so finish immediately rather than leaving the caller waiting on a
        // callback that can never arrive.
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first else {
            completion()
            return
        }

        self.completion = completion

        for screen in NSScreen.screens {
            let isPrimary = screen == mainScreen
            let window = CinematicWindow(
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
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.acceptsKeysOverride = isPrimary
            window.onCancel = { [weak self] in self?.finish() }

            let root: AnyView = isPrimary
                ? AnyView(WelcomeCinematicView { [weak self] in self?.finish() })
                : AnyView(Color.black.opacity(0.82).ignoresSafeArea())

            window.contentView = NSHostingView(rootView: root)
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        // An accessory app receives no key events until it activates, so Escape and the
        // button's Return shortcut would both be dead without this.
        NSApp.activate(ignoringOtherApps: true)
        windows.first { ($0 as? CinematicWindow)?.acceptsKeysOverride == true }?.makeKey()
    }

    /// Tears the overlay down and hands control back exactly once.
    private func finish() {
        guard let completion else { return }
        // Cleared before calling out, so a second Continue click during teardown cannot
        // run the caller's follow-up twice.
        self.completion = nil

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()

        completion()
    }
}

/// Borderless windows refuse key status, which would leave Escape and the Continue
/// button's Return shortcut dead. Only the screen showing the animation asks for it —
/// the plain dim on the other displays has nothing to focus.
private final class CinematicWindow: NSWindow {
    var acceptsKeysOverride = false
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeysOverride }
    override var canBecomeMain: Bool { acceptsKeysOverride }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Return and Enter finish the welcome, the same as Escape and Continue.
    ///
    /// Handled here rather than with `.keyboardShortcut(.defaultAction)` on the button:
    /// in a borderless key window that modifier fires the button's action by itself, with
    /// no keypress at all, which dismissed the welcome the instant the button appeared.
    /// 36 is Return, 76 the keypad's.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

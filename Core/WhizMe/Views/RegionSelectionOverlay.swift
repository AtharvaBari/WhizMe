import AppKit

/// Full-screen drag-to-select UI, one dimmed overlay window per display.
///
/// Presentation only: it hands back a rectangle and knows nothing about capture or
/// OCR. The result is returned in **CoreGraphics display coordinates** (top-left
/// origin, +Y down) because that is what every capture API downstream expects.
@MainActor
final class RegionSelectionOverlay {
    static let shared = RegionSelectionOverlay()

    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var previouslyActiveApp: NSRunningApplication?

    private init() {}

    /// - Returns: the selected rect in CG display coordinates, or `nil` if the user
    ///   pressed Escape, right-clicked, or drew nothing meaningful.
    func selectRegion() async -> CGRect? {
        // A second overlay while one is up would strand the first continuation.
        guard continuation == nil else { return nil }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    // MARK: - Presentation

    private func present() {
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        // An accessory (LSUIElement) app receives no key events until it activates,
        // so Escape would be swallowed without this.
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onUpdate = { [weak self] rect in self?.broadcastHighlight(rect) }
            view.onCommit = { [weak self] rect in self?.finish(with: rect) }
            window.contentView = view

            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        // Give focus to the display the cursor is already on so the first keystroke
        // lands, and so a drag started there is tracked by a key window.
        let cursor = NSEvent.mouseLocation
        let focused = windows.first { $0.frame.contains(cursor) } ?? windows.first
        focused?.makeKey()
    }

    /// Every overlay draws the same global rect so a drag spanning two displays shows
    /// its full extent rather than clipping at the bezel.
    private func broadcastHighlight(_ globalRect: NSRect?) {
        for window in windows {
            (window.contentView as? RegionSelectionView)?.setHighlight(globalRect)
        }
    }

    private func finish(with globalRect: NSRect?) {
        // Take the continuation before any teardown so it can only be resumed once,
        // even if a second commit arrives from another overlay's view.
        guard let continuation else { return }
        self.continuation = nil

        let result: CGRect?
        if let globalRect, globalRect.width >= 4, globalRect.height >= 4 {
            result = Self.displayCoordinates(from: globalRect)
        } else {
            result = nil // a click without a drag means "never mind"
        }

        teardown()
        continuation.resume(returning: result)
    }

    private func teardown() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()

        // Hand focus back before the capture happens; leaving WhizMe frontmost would
        // put our own menu bar in the shot on the next invocation.
        previouslyActiveApp?.activate()
        previouslyActiveApp = nil
    }

    // MARK: - Coordinate conversion

    /// AppKit global coordinates put the origin at the **bottom-left of the primary
    /// display** with +Y pointing up. CoreGraphics display coordinates put it at the
    /// **top-left of the same display** with +Y pointing down. Only Y changes:
    ///
    ///     cgY = primaryHeight − appKitMaxY
    ///
    /// `maxY` (not `minY`) is the input because flipping the axis also swaps which
    /// edge is "nearest the origin". This stays correct for a secondary display above
    /// the primary — its AppKit `maxY` exceeds `primaryHeight`, yielding the negative
    /// CG Y that CoreGraphics genuinely uses for displays stacked above the main one.
    static func displayCoordinates(from appKitRect: NSRect) -> CGRect {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.screens.first else {
            return appKitRect
        }
        return CGRect(
            x: appKitRect.minX,
            y: primary.frame.height - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }
}

/// Borderless windows refuse key status by default, which would eat the Escape key.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Dims its screen, tracks the drag, and draws the live selection.
private final class RegionSelectionView: NSView {
    /// Live selection in global AppKit coordinates, `nil` while nothing is drawn.
    var onUpdate: ((NSRect?) -> Void)?
    /// Final selection in global AppKit coordinates, `nil` to cancel.
    var onCommit: ((NSRect?) -> Void)?

    private var anchorInWindow: NSPoint?
    private var highlight: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setHighlight(_ globalRect: NSRect?) {
        highlight = globalRect
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let highlight, let window else { return }
        let local = convert(window.convertFromScreen(highlight), from: nil)
        guard !local.isEmpty else { return }

        // Punch the selection out of the dimming layer so the user sees true colours
        // underneath — .copy writes clear pixels instead of blending onto them.
        NSColor.clear.setFill()
        local.fill(using: .copy)

        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: local.insetBy(dx: -0.5, dy: -0.5))
        outline.lineWidth = 1
        outline.stroke()

        drawSizeReadout(for: local)
    }

    private func drawSizeReadout(for rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 4

        // Sit above the selection, or inside it when the drag reaches the screen top.
        var origin = NSPoint(x: rect.minX, y: rect.maxY + padding + 2)
        if origin.y + size.height > bounds.maxY {
            origin.y = rect.maxY - size.height - padding - 2
        }

        let backdrop = NSRect(
            x: origin.x - padding,
            y: origin.y - padding / 2,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: backdrop, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        anchorInWindow = event.locationInWindow
        onUpdate?(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = anchorInWindow, let window else { return }
        onUpdate?(window.convertToScreen(Self.rect(from: anchor, to: event.locationInWindow)))
    }

    override func mouseUp(with event: NSEvent) {
        guard let anchor = anchorInWindow, let window else {
            onCommit?(nil)
            return
        }
        anchorInWindow = nil
        onCommit?(window.convertToScreen(Self.rect(from: anchor, to: event.locationInWindow)))
    }

    override func rightMouseDown(with event: NSEvent) {
        onCommit?(nil)
    }

    override func keyDown(with event: NSEvent) {
        // 53 is Escape. Handling it here as well as in cancelOperation covers the
        // case where the overlay is key but not first responder.
        if event.keyCode == 53 {
            onCommit?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCommit?(nil)
    }

    /// Normalised rect between two points — a drag in any direction produces a
    /// positive-size rect.
    private static func rect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

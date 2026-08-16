import AppKit
import os

/// Swallows every key event system-wide, so the keyboard can be wiped without typing
/// into whatever happens to be frontmost.
///
/// Built on a session-level `CGEvent` tap because that is the only mechanism that can
/// intercept keys before they reach other applications — it needs Accessibility, which
/// is why the utility declares that permission.
///
/// The block cannot outlive the app: an event tap belongs to the process that created
/// it, so if WhizMe crashes or is force-quit while blocking, macOS tears the tap down
/// and the keyboard comes straight back. That property is the whole reason this is safe
/// to ship.
@MainActor
final class KeyboardBlockService {
    static let shared = KeyboardBlockService()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "KeyboardBlock")

    var isBlocking: Bool { tap != nil }

    private init() {}

    /// - Returns: `false` when macOS refused the tap, which in practice means
    ///   Accessibility has not been granted.
    @discardableResult
    func begin() -> Bool {
        guard tap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: keyboardTapCallback,
            userInfo: nil
        ) else {
            log.error("CGEvent.tapCreate refused — Accessibility is probably not granted")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func end() {
        guard let tap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)

        self.runLoopSource = nil
        self.tap = nil
    }

    /// macOS switches a tap off if its callback is ever too slow. Nothing here is slow,
    /// but a disabled tap would silently hand the keyboard back mid-wipe, so it is
    /// turned straight back on.
    fileprivate func reenableAfterTimeout() {
        guard let tap else { return }
        log.notice("Event tap was disabled by the system; re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

/// C trampoline. Returning `nil` discards the event, which is what "the keyboard does
/// nothing" means in practice.
private let keyboardTapCallback: CGEventTapCallBack = { _, type, _, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            KeyboardBlockService.shared.reenableAfterTimeout()
        }
        return nil
    }
    return nil
}

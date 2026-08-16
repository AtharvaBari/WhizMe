import IOKit.pwr_mgt
import os

/// Thin wrapper over IOKit's power-management assertions. Holds at most one
/// assertion; knows nothing about timers, durations, or UI.
///
/// WhizMe asserts `kIOPMAssertionTypeNoIdleSleep`: the *system* stays awake —
/// CPU, network and disks keep running — while the display is still free to dim
/// and sleep on its own schedule. The sibling `kIOPMAssertionTypeNoDisplaySleep`
/// additionally pins the screen on, which drains the battery and is not what
/// "Awake" promises, so it is deliberately not exposed here.
///
/// Every failure path is non-fatal: if macOS refuses the assertion the Mac simply
/// sleeps as it normally would, and the caller is told so it can avoid showing an
/// "on" state that is not real.
@MainActor
final class KeepAwakeService {
    /// The live assertion id, boxed so the nonisolated `deinit` below may reach it.
    private let assertion = AssertionBox()
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "Awake")

    var isAsserted: Bool { assertion.id != nil }

    /// Creates the no-idle-sleep assertion, tagged with `reason` — the string macOS
    /// shows in `pmset -g assertions` and Activity Monitor's Energy tab.
    /// - Returns: `true` when the Mac is being held awake, already or as of now.
    @discardableResult
    func begin(reason: String) -> Bool {
        // Idempotent on purpose. Creating a second assertion would overwrite the
        // stored id and orphan the first one: nothing would ever hold a handle to
        // release it, so the Mac would be pinned awake until the process died.
        guard assertion.id == nil else { return true }

        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )

        guard result == kIOReturnSuccess else {
            log.error("IOPMAssertionCreateWithName failed (IOReturn \(result, privacy: .public)) — this Mac will keep sleeping normally")
            return false
        }

        assertion.id = id
        return true
    }

    /// Releases the assertion and forgets the id, so a second `end()` — or an
    /// `end()` that was never preceded by a `begin()` — does nothing.
    func end() {
        guard let id = assertion.take() else { return }

        let result = IOPMAssertionRelease(id)
        if result != kIOReturnSuccess {
            log.error("IOPMAssertionRelease failed (IOReturn \(result, privacy: .public)) — the sleep assertion may still be held")
        }
    }

    deinit {
        // Last line of defence. An assertion that outlives its owner keeps the Mac
        // awake with no UI left to switch it off, so it is worth releasing even on
        // a path that should never happen. Legal from a nonisolated deinit only
        // because the box is `Sendable` — see `AssertionBox`.
        if let id = assertion.take() {
            IOPMAssertionRelease(id)
        }
    }
}

/// Mutable box for the assertion id.
///
/// A `@MainActor` class's `deinit` is nonisolated and may not touch main-actor
/// state, so under Swift 6 the id cannot live as a plain stored property on
/// `KeepAwakeService` and still be reachable from cleanup. Parking it in a
/// `Sendable` reference type keeps that path compiling without weakening the
/// isolation on the service itself. The `@unchecked` is honest: every mutation
/// happens on the main actor, except in `deinit`, where by definition no other
/// reference to the box survives — and `IOPMAssertionRelease` is a thread-safe
/// C call in any case.
private final class AssertionBox: @unchecked Sendable {
    var id: IOPMAssertionID?

    /// Reads and clears in one step, so a caller cannot release the same id twice.
    func take() -> IOPMAssertionID? {
        defer { id = nil }
        return id
    }
}

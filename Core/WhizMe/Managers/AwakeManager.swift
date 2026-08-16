import Foundation
import Observation

/// Owns *when* this Mac is held awake and for how long. `KeepAwakeService` does the
/// IOKit work; this type holds the state the menu bar and Settings render, and runs
/// the expiry clock for the timed durations.
@MainActor
@Observable
final class AwakeManager {
    /// True only while a real assertion is held — never merely because one was asked for.
    private(set) var isActive = false

    /// When the current session switches itself off; `nil` while indefinite or off.
    private(set) var expiresAt: Date?

    private(set) var activeDuration: AwakeDuration?

    /// Set when macOS refused the assertion, so the UI can say why nothing happened
    /// instead of leaving the user to discover it when their Mac sleeps mid-render.
    private(set) var lastError: String?

    /// Bumped once a second while a finite duration runs. It exists purely to give
    /// `statusDescription` — a computed property — an observable input that changes
    /// as the clock does; without it the menu would show a frozen countdown.
    private var tickDate = Date.now

    @ObservationIgnored private let service: KeepAwakeService
    @ObservationIgnored private var countdown: Task<Void, Never>?

    private static let assertionReason = "\(AppInfo.name) — Awake is on"

    init() {
        self.service = KeepAwakeService()
    }

    /// One line for the menu bar: "Off", "On — indefinitely", "On — 42:15 left".
    var statusDescription: String {
        guard isActive else { return "Off" }
        guard let expiresAt else { return "On — indefinitely" }

        let remaining = max(0, expiresAt.timeIntervalSince(tickDate))
        return "On — \(Self.remainingDescription(remaining)) left"
    }

    /// What the menu bar item and the global shortcut both call: flips Awake on
    /// indefinitely, or off if anything is currently running.
    func toggle(defaultDuration: AwakeDuration = .indefinite) {
        if isActive {
            deactivate()
        } else {
            activate(for: defaultDuration)
        }
    }

    /// Starts — or restarts, if Awake is already on — a session of `duration`.
    func activate(for duration: AwakeDuration) {
        // Cancel first. Re-activating while a timed session is running must not leave
        // the old expiry alive to switch Awake off partway through the new one.
        cancelCountdown()

        guard service.begin(reason: Self.assertionReason) else {
            // Never show an "on" UI over an assertion that does not exist.
            resetState()
            lastError = "macOS refused the sleep assertion, so this Mac can still sleep."
            return
        }

        // Both dates come off one reading of the clock: sampling twice leaves the
        // deadline a hair beyond the tick, and the very first line the user reads
        // rounds up to "5:01 left" on a five-minute session.
        let start = Date.now

        lastError = nil
        isActive = true
        activeDuration = duration
        tickDate = start

        if let interval = duration.timeInterval {
            expiresAt = start.addingTimeInterval(interval)
            startCountdown()
        } else {
            // Nothing is counting down, so nothing needs to wake the CPU every second.
            expiresAt = nil
        }
    }

    /// Releases the assertion and stops the clock. Safe to call when already off,
    /// which is what makes it usable as an unconditional shutdown step.
    func deactivate() {
        cancelCountdown()
        service.end()
        resetState()
    }

    private func startCountdown() {
        countdown = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func cancelCountdown() {
        countdown?.cancel()
        countdown = nil
    }

    /// Refreshes the observable clock and retires the session once its deadline has
    /// passed. Expiry rides on the same tick rather than a second timer: a second of
    /// slack on a five-minute countdown is invisible, and one timer is one thing to
    /// cancel instead of two things to keep in sync.
    private func tick() {
        tickDate = .now
        guard let expiresAt, tickDate >= expiresAt else { return }
        deactivate()
    }

    private func resetState() {
        isActive = false
        expiresAt = nil
        activeDuration = nil
    }

    /// `m:ss` under an hour and `h:mm` above it, so the digit that is visibly moving
    /// is always the smallest one shown and the line never looks stuck.
    private static func remainingDescription(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        return hours > 0
            ? String(format: "%d:%02d", hours, minutes)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

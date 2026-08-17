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

    /// The condition holding this Mac awake, or `nil` when Awake is off or running on a
    /// clock instead. Mutually exclusive with `expiresAt` — a session is either timed or
    /// conditional, never both, because two ways to end one session is two things that can
    /// disagree about whether it has ended.
    private(set) var activeCondition: AwakeCondition?

    /// Set when macOS refused the assertion, so the UI can say why nothing happened
    /// instead of leaving the user to discover it when their Mac sleeps mid-render.
    private(set) var lastError: String?

    /// Bumped once a second while a finite duration runs. It exists purely to give
    /// `statusDescription` — a computed property — an observable input that changes
    /// as the clock does; without it the menu would show a frozen countdown.
    private var tickDate = Date.now

    @ObservationIgnored private let service: KeepAwakeService
    @ObservationIgnored private var countdown: Task<Void, Never>?
    @ObservationIgnored private lazy var conditionWatch = ConditionWatchService { [weak self] isSatisfied in
        self?.conditionChanged(isSatisfied)
    }

    private static let assertionReason = "\(AppInfo.name) — Awake is on"

    init() {
        self.service = KeepAwakeService()
    }

    /// One line for the menu bar: "Off", "On — indefinitely", "On — 42:15 left".
    var statusDescription: String {
        guard isActive else { return "Off" }
        if let activeCondition {
            // Only the first character. Lowercasing the whole title turned "While Finder is
            // running" into "while finder is running" and took the app's name with it.
            let title = activeCondition.title
            return "On — " + title.prefix(1).lowercased() + title.dropFirst()
        }
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
        // Cancel both. Re-activating must not leave an old expiry alive to switch Awake off
        // partway through the new session, nor a condition watching for a job that this
        // session has nothing to do with.
        cancelCountdown()
        conditionWatch.stop()
        activeCondition = nil

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

    /// Starts a session that lasts as long as `condition` holds.
    ///
    /// Refuses when the condition is not true yet. Holding the Mac awake for an app that is
    /// not running, or a download that has not started, would show an "on" state that
    /// nothing is keeping alive — and it would end the instant the watcher first evaluated.
    /// - Returns: `false` when the condition is not currently satisfied.
    @discardableResult
    func activate(while condition: AwakeCondition) -> Bool {
        guard conditionWatch.isSatisfied(condition) else {
            lastError = notSatisfiedMessage(for: condition)
            return false
        }

        cancelCountdown()

        guard service.begin(reason: Self.assertionReason) else {
            resetState()
            lastError = "macOS refused the sleep assertion, so this Mac can still sleep."
            return false
        }

        lastError = nil
        isActive = true
        activeDuration = nil
        // No expiry: the condition is the clock, so nothing needs to tick every second.
        expiresAt = nil
        activeCondition = condition

        // Started last, because `start` reports the current value immediately and that
        // callback reads the state set above.
        conditionWatch.start(condition)
        return true
    }

    /// Releases the assertion and stops the clock. Safe to call when already off,
    /// which is what makes it usable as an unconditional shutdown step.
    func deactivate() {
        cancelCountdown()
        conditionWatch.stop()
        service.end()
        resetState()
    }

    /// The condition stopped holding, so the session is over.
    ///
    /// Only ever switches Awake *off*. A condition becoming true again — an app relaunched,
    /// a new download started — must not silently resurrect a session the user has already
    /// seen end, because nothing would tell them it had come back.
    private func conditionChanged(_ isSatisfied: Bool) {
        guard !isSatisfied, isActive, activeCondition != nil else { return }
        deactivate()
    }

    private func notSatisfiedMessage(for condition: AwakeCondition) -> String {
        switch condition {
        case .whileAppRuns(_, let name):
            "\(name) is not running, so there is nothing to wait for."
        case .whileDownloading:
            "Nothing is downloading right now, so there is nothing to wait for."
        }
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
        activeCondition = nil
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

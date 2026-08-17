import AppKit
import os

/// Watches an `AwakeCondition` and reports when it stops being true.
///
/// Both conditions are event-driven where macOS allows it and polled only where it does
/// not, because this runs for as long as the user's long job does — an implementation that
/// spins is one that keeps the Mac awake *and* burns the battery it was asked to preserve.
///
/// * **App running** is fully event-driven. `NSWorkspace` posts launch and termination
///   notifications, so there is nothing to poll and the release is immediate.
/// * **Downloading** has no notification. macOS publishes no "a download is in progress"
///   signal — Safari, Chrome and Firefox each write their own kind of part-file and tell
///   nobody. So this one polls the Downloads folder, slowly.
@MainActor
final class ConditionWatchService {
    /// Called whenever the condition's truth changes, with the new value.
    private let onChange: (Bool) -> Void

    private var condition: AwakeCondition?
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var lastValue = false

    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "AwakeCondition")

    /// Ten seconds. A download that finished is only interesting to within a few seconds,
    /// and a directory listing every ten is unmeasurable next to the download itself.
    private static let pollInterval: TimeInterval = 10

    /// Part-file markers, one per browser. There is no shared convention, so the list is
    /// the API: Safari writes a `.download` bundle, Chromium `.crdownload`, Firefox
    /// `.part`, curl and others `.partial`.
    private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial"]

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    /// Begins watching. Reports the condition's current value immediately, so a caller
    /// never has to assume a starting state.
    func start(_ condition: AwakeCondition) {
        stop()
        self.condition = condition

        switch condition {
        case .whileAppRuns:
            // Terminations are what matter, but launches are watched too: an app that is
            // relaunched mid-job should not drop the assertion permanently.
            for name in [NSWorkspace.didTerminateApplicationNotification,
                         NSWorkspace.didLaunchApplicationNotification] {
                let observer = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    // Delivered on the main queue because that is the queue requested.
                    MainActor.assumeIsolated { self?.evaluate() }
                }
                observers.append(observer)
            }

        case .whileDownloading:
            let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                // Scheduled from the main actor, so it fires on the main run loop.
                MainActor.assumeIsolated { self?.evaluate() }
            }
            pollTimer = timer
        }

        lastValue = isSatisfied(condition)
        onChange(lastValue)
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()

        pollTimer?.invalidate()
        pollTimer = nil

        condition = nil
        lastValue = false
    }

    /// Re-checks and reports only on a change, so the owner is not woken to be told the
    /// same thing.
    private func evaluate() {
        guard let condition else { return }
        let value = isSatisfied(condition)
        guard value != lastValue else { return }
        lastValue = value
        log.info("Condition \(condition.title, privacy: .public) is now \(value, privacy: .public)")
        onChange(value)
    }

    // MARK: - Evaluation

    func isSatisfied(_ condition: AwakeCondition) -> Bool {
        switch condition {
        case .whileAppRuns(let bundleID, _):
            return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
        case .whileDownloading:
            return Self.hasPartialDownloads
        }
    }

    /// True when the Downloads folder holds a part-finished file.
    ///
    /// Deliberately shallow and non-recursive. A recursive walk of a folder that often
    /// holds unpacked archives and disk images would cost far more than this is worth, and
    /// browsers all write their part-file at the top level.
    private static var hasPartialDownloads: Bool {
        guard let downloads = try? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return false }

        guard let names = try? FileManager.default.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return false }

        return names.contains { partialExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// Apps the user could pick, minus WhizMe itself and anything with no interface.
    ///
    /// Only running apps are offered. Presenting every app on the disk would mean a
    /// searchable file browser for a feature whose entire point is "the thing I am running
    /// right now" — and an app that is not running fails the condition instantly, so
    /// picking one from a list of all apps would switch Awake straight back off.
    static func selectableRunningApps() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != AppInfo.bundleIdentifier }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (id, name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

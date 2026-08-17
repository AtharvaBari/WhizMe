import Foundation
import IOKit.ps
import Observation
import os

/// Observable battery and thermal state.
///
/// ## Why there is no timer here
///
/// Both sources push. IOPowerSources hands out a run loop source that fires whenever the
/// charge, the charging state, or the adapter changes; `ProcessInfo` posts a notification
/// when the thermal state moves. A menu bar utility that polled the battery every few
/// seconds would wake the CPU forever to re-read a number that changes once a minute at
/// most — on the very feature whose subject is power. Idle cost here is zero.
///
/// Cycle count and health are read in the same pass. They change over weeks, so they need
/// no schedule of their own; any charge change refreshes them for free.
@MainActor
@Observable
final class PowerManager {
    private(set) var snapshot: PowerSnapshot = .unavailable

    /// True on a Mac that has a battery at all, so the UI can drop battery rows on a
    /// desktop rather than showing them empty.
    var hasBattery: Bool { snapshot.battery != nil }

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "Power")

    /// The instance the C callback below reaches back into.
    ///
    /// `IOPSNotificationCreateRunLoopSource` takes a bare C function pointer, which cannot
    /// capture. Exactly one `PowerManager` exists — `AppEnvironment` owns it — so a static
    /// weak reference is enough, and being weak means a torn-down manager cannot be called
    /// into. Main-actor isolated along with the rest of the type.
    @ObservationIgnored private static weak var monitoring: PowerManager?

    init() {
        // Read once up front so the first render has real values instead of a blank row
        // that fills in a moment later.
        snapshot = PowerMetricsService.snapshot()
    }

    func startMonitoring() {
        guard runLoopSource == nil else { return }
        Self.monitoring = self

        if let source = IOPSNotificationCreateRunLoopSource(powerSourceChanged, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        } else {
            log.error("IOPSNotificationCreateRunLoopSource failed — battery readings will not update on their own")
        }

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Posted on the main queue because that is the queue asked for above.
            MainActor.assumeIsolated { Self.monitoring?.refresh() }
        }

        refresh()
    }

    func stopMonitoring() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil

        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
        thermalObserver = nil

        if Self.monitoring === self { Self.monitoring = nil }
    }

    /// Re-reads everything. Cheap enough to call freely — it is two IOKit reads.
    func refresh() {
        let next = PowerMetricsService.snapshot()
        // Only publish real changes. The charge notification fires more often than the
        // values actually move, and waking every observer to re-render an identical row is
        // the cost this design exists to avoid.
        guard next != snapshot else { return }
        snapshot = next
    }

    /// One line for the menu bar: "76% · 94 cycles · 90%".
    var summary: String {
        guard let battery = snapshot.battery else {
            return "Thermal: \(snapshot.thermal.title)"
        }

        var parts = ["\(battery.chargePercent)%"]
        if battery.isCharging { parts[0] += " charging" }
        if let cycles = battery.cycleCount { parts.append("\(cycles) cycles") }
        if let health = battery.healthPercent { parts.append("\(health)% health") }
        // Only worth a line when it is actually affecting the Mac.
        if snapshot.thermal.isThrottling { parts.append(snapshot.thermal.title) }
        return parts.joined(separator: " · ")
    }
}

/// C trampoline for IOPowerSources.
///
/// Fires on the run loop the source was added to — the main one — which is what makes the
/// isolation assertion below sound rather than hopeful.
private let powerSourceChanged: IOPowerSourceCallbackType = { _ in
    MainActor.assumeIsolated {
        PowerManager.refreshMonitoringInstance()
    }
}

extension PowerManager {
    /// Reaches the live instance from the C callback, which cannot see private members.
    fileprivate static func refreshMonitoringInstance() {
        monitoring?.refresh()
    }
}

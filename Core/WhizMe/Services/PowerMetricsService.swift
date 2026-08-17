import Foundation
import IOKit
import IOKit.ps

/// Reads battery and thermal state from IOKit. No state, no polling, no UI.
///
/// Two sources, deliberately:
///
/// * **IOPowerSources** for charge, charging, and time remaining. It normalises across
///   hardware, which matters more than it sounds: `AppleSmartBattery`'s `CurrentCapacity`
///   is a *percentage* on Apple Silicon and *milliamp-hours* on Intel, so reading the
///   charge from the registry means shipping a number that is right on one architecture
///   and nonsense on the other.
/// * **AppleSmartBattery** in the IO registry for cycle count, capacities, and
///   temperature, which IOPowerSources does not publish.
///
/// Every key is read defensively. Apple has renamed and dropped these across machines,
/// and a missing key must leave one row blank rather than take the utility down.
enum PowerMetricsService {

    /// Reads everything in one pass.
    ///
    /// `nonisolated` and free of shared state: IOKit's C API is thread-safe for reads, so a
    /// caller can do this off the main actor if it ever needs to.
    static func snapshot() -> PowerSnapshot {
        PowerSnapshot(
            battery: readBattery(),
            thermal: PowerSnapshot.ThermalState(ProcessInfo.processInfo.thermalState)
        )
    }

    // MARK: - IOPowerSources

    private static func readBattery() -> PowerSnapshot.Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        // The first *internal* battery. A connected UPS or a Bluetooth mouse also appear as
        // power sources, and reporting a mouse's charge as this Mac's battery is exactly the
        // kind of quiet wrongness that makes a readout untrustworthy.
        let internalBattery = sources.lazy
            .compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }

        guard let source = internalBattery else { return nil }

        let current = source[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = source[kIOPSMaxCapacityKey] as? Int ?? 100
        // IOPowerSources reports capacity against its own maximum, which is 100 in practice
        // but documented as arbitrary — so scale rather than assume.
        let percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0

        let isCharging = source[kIOPSIsChargingKey] as? Bool ?? false
        let isPluggedIn = (source[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

        // Negative means "still calculating", which macOS reports for a while after any
        // change. Showing "-1 minutes remaining" is worse than showing nothing.
        let minutesKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        let minutes = source[minutesKey] as? Int ?? -1
        let timeRemaining: TimeInterval? = minutes > 0 ? TimeInterval(minutes * 60) : nil

        let registry = readSmartBattery()

        return PowerSnapshot.Battery(
            chargePercent: percent.clamped(to: 0...100),
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            cycleCount: registry.cycleCount,
            healthPercent: registry.healthPercent,
            temperatureCelsius: registry.temperatureCelsius,
            timeRemaining: timeRemaining,
            hasPermanentFailure: registry.hasPermanentFailure
        )
    }

    // MARK: - IO registry

    private struct RegistryReadings {
        var cycleCount: Int?
        var healthPercent: Int?
        var temperatureCelsius: Double?
        var hasPermanentFailure = false
    }

    private static func readSmartBattery() -> RegistryReadings {
        var readings = RegistryReadings()

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return readings }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return readings
        }

        readings.cycleCount = properties["CycleCount"] as? Int

        // "Maximum Capacity" as System Information reports it.
        //
        // NominalChargeCapacity first: it is what Apple Silicon Macs publish and what the
        // System Information figure is computed from. AppleRawMaxCapacity is the Intel-era
        // equivalent and reads a few points lower on the same battery. MaxCapacity is
        // deliberately NOT used — on Apple Silicon it is normalised to a flat 100 and would
        // report every battery as perfect.
        let design = properties["DesignCapacity"] as? Int
        let full = (properties["NominalChargeCapacity"] as? Int)
            ?? (properties["AppleRawMaxCapacity"] as? Int)

        if let design, let full, design > 0 {
            readings.healthPercent = Int((Double(full) / Double(design) * 100).rounded()).clamped(to: 0...100)
        }

        // Hundredths of a degree Celsius. Sanity-bounded because a garbage reading here
        // would be shown to the user as fact — the pack reports 0 briefly during some
        // transitions, and no Mac battery is genuinely at 0°C in use.
        if let raw = properties["Temperature"] as? Int, raw > 0 {
            let celsius = Double(raw) / 100
            if (1...100).contains(celsius) {
                readings.temperatureCelsius = celsius
            }
        }

        if let failure = properties["PermanentFailureStatus"] as? Int {
            readings.hasPermanentFailure = failure != 0
        }

        return readings
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

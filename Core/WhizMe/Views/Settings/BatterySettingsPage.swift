import SwiftUI

/// The Battery & Thermal readout.
///
/// Read-only by design: nothing here is a setting. It exists because the numbers macOS
/// keeps are buried in System Information behind an ⌥-click, and cycle count is the one
/// figure people actually go looking for.
struct BatterySettingsPage: View {
    @Environment(AppEnvironment.self) private var app

    let onBack: () -> Void

    private var snapshot: PowerSnapshot { app.power.snapshot }

    var body: some View {
        FeatureSettingsScaffold(feature: .batteryHealth, onBack: onBack) {
            if let battery = snapshot.battery {
                SettingsCard(title: "Battery") {
                    SettingsCardRow(
                        symbolName: chargeSymbol(for: battery),
                        title: chargeTitle(for: battery),
                        subtitle: chargeSubtitle(for: battery)
                    ) {
                        Text("\(battery.chargePercent)%")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                    }

                    SettingsCardDivider()

                    SettingsCardRow(
                        symbolName: "arrow.triangle.2.circlepath",
                        title: "Charge cycles",
                        subtitle: "One cycle is a full charge's worth of use, however it was spread out"
                    ) {
                        readout(battery.cycleCount.map(String.init))
                    }

                    SettingsCardDivider()

                    SettingsCardRow(
                        symbolName: "heart.text.square",
                        title: "Maximum capacity",
                        subtitle: "How much charge it holds now, against when it was new"
                    ) {
                        readout(battery.healthPercent.map { "\($0)%" })
                    }

                    SettingsCardDivider()

                    SettingsCardRow(
                        symbolName: battery.condition == .normal ? "checkmark.seal" : "exclamationmark.triangle",
                        title: "Condition",
                        subtitle: conditionSubtitle(for: battery)
                    ) {
                        Text(battery.condition.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(battery.condition == .normal ? Color.secondary : Color.orange)
                    }

                    if let temperature = battery.temperatureCelsius {
                        SettingsCardDivider()

                        SettingsCardRow(
                            symbolName: "thermometer.variable",
                            title: "Battery temperature",
                            subtitle: "Measured at the cells, not at the case"
                        ) {
                            Text(temperature.formatted(.number.precision(.fractionLength(1))) + " °C")
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsCard(
                title: "Thermal state",
                footer: snapshot.thermal.advice
            ) {
                SettingsCardRow(
                    symbolName: snapshot.thermal.symbolName,
                    title: snapshot.thermal.isThrottling ? "This Mac is being throttled" : "Running normally",
                    subtitle: thermalSubtitle
                ) {
                    Text(snapshot.thermal.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(snapshot.thermal.isThrottling ? Color.orange : Color.secondary)
                }
            }

            if !app.power.hasBattery {
                SafetyNote(
                    text: "This Mac has no battery, so only thermal state is shown."
                )
            }
        }
    }

    // MARK: - Pieces

    /// Dashes rather than a zero for a reading macOS did not supply. A missing value and a
    /// value of zero mean completely different things, and only one of them is true.
    @ViewBuilder
    private func readout(_ value: String?) -> some View {
        Text(value ?? "—")
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(value == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
    }

    private func chargeSymbol(for battery: PowerSnapshot.Battery) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.chargePercent {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<70: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func chargeTitle(for battery: PowerSnapshot.Battery) -> String {
        if battery.isCharging { return "Charging" }
        return battery.isPluggedIn ? "Plugged in, not charging" : "On battery"
    }

    private func chargeSubtitle(for battery: PowerSnapshot.Battery) -> String {
        guard let remaining = battery.timeRemaining else {
            // macOS reports a negative estimate for a minute or so after any change, and
            // "calculating" is honest where a stale figure would not be.
            return battery.isPluggedIn && !battery.isCharging
                ? "Held at this level to reduce wear"
                : "Time remaining: still calculating"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        let text = formatter.string(from: remaining) ?? "—"
        return battery.isCharging ? "\(text) until full" : "\(text) remaining"
    }

    private func conditionSubtitle(for battery: PowerSnapshot.Battery) -> String {
        if battery.hasPermanentFailure {
            return "The battery reported a fault to macOS"
        }
        return "Apple considers a battery due for service below 80% capacity"
    }

    private var thermalSubtitle: String {
        snapshot.thermal.isThrottling
            ? "Performance is reduced until it cools"
            : "Reported by macOS, which watches this more closely than any app can"
    }
}

import Foundation

/// The textual representations a sampled color can be copied as.
///
/// Drives both the format picker in the UI and the string written to the
/// clipboard, so there is exactly one list of supported formats.
enum ColorFormat: String, CaseIterable, Identifiable, Sendable {
    case hex
    case rgb
    case hsl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hex: "HEX"
        case .rgb: "RGB"
        case .hsl: "HSL"
        }
    }
}

/// One pixel the user sampled off the screen, stored in sRGB.
///
/// Deliberately pure data: no AppKit, no color spaces, no side effects. The
/// `NSColor` bridge lives in `ColorSamplerService` so this type stays trivially
/// testable and encodable, and every conversion below is total — a nonsense
/// component can produce a wrong string but can never trap.
struct SampledColor: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    /// sRGB components, `0...1`.
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let sampledAt: Date

    init(red: Double, green: Double, blue: Double, alpha: Double = 1, sampledAt: Date = .now) {
        self.id = UUID()
        // Clamp on the way in so the documented `0...1` invariant actually holds,
        // whatever a display's color space handed us.
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
        self.alpha = Self.clamped(alpha)
        self.sampledAt = sampledAt
    }

    /// Uppercase, always six digits: `#FF8800`.
    var hex: String {
        String(format: "#%02X%02X%02X", Self.byte(red), Self.byte(green), Self.byte(blue))
    }

    /// CSS-style: `rgb(255, 136, 0)`.
    var rgbDescription: String {
        "rgb(\(Self.byte(red)), \(Self.byte(green)), \(Self.byte(blue)))"
    }

    /// CSS-style: `hsl(32, 100%, 50%)`.
    var hslDescription: String {
        let hsl = hslComponents
        return "hsl(\(hsl.hue), \(hsl.saturation)%, \(hsl.lightness)%)"
    }

    func string(for format: ColorFormat) -> String {
        switch format {
        case .hex: hex
        case .rgb: rgbDescription
        case .hsl: hslDescription
        }
    }

    /// sRGB -> HSL, rounded the way CSS writes it: whole degrees and whole percents.
    private var hslComponents: (hue: Int, saturation: Int, lightness: Int) {
        // Re-clamp rather than trusting the stored values: `init(from:)` decodes
        // straight into the properties and never runs the clamping initializer,
        // and a non-finite component would trap in `Int(_:)` further down.
        let red = Self.clamped(red)
        let green = Self.clamped(green)
        let blue = Self.clamped(blue)

        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        let lightness = (maxValue + minValue) / 2

        // Achromatic — black, white, any grey. Every hue and saturation formula
        // below divides by `delta`, so bail out before that division happens.
        guard delta > 0 else { return (0, 0, Self.percent(lightness)) }

        // `1 - |2L - 1|` is only zero when delta is zero, but floating point can
        // still make it vanishingly small near pure black/white, so guard anyway.
        let denominator = 1 - abs(2 * lightness - 1)
        let saturation = denominator > 0 ? min(1, delta / denominator) : 0

        var hue: Double
        switch maxValue {
        case red: hue = 60 * ((green - blue) / delta)
        case green: hue = 60 * ((blue - red) / delta + 2)
        default: hue = 60 * ((red - green) / delta + 4)
        }
        if hue < 0 { hue += 360 }

        // Rounding can push 359.7 to 360, which is not a legal hue — wrap it to 0.
        let degrees = (Int(hue.rounded()) % 360 + 360) % 360
        return (degrees, Self.percent(saturation), Self.percent(lightness))
    }

    /// NaN collapses to 0 rather than trapping in the `Int(_:)` conversions below;
    /// it has to be caught explicitly because it compares false against everything,
    /// so `min`/`max` alone cannot pin it down. Infinities saturate normally.
    private static func clamped(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return min(1, max(0, value))
    }

    /// 8-bit channel value, rounded rather than truncated — truncating turns
    /// 0.999 into 254 and quietly shifts every color one step dark.
    private static func byte(_ value: Double) -> Int {
        Int((clamped(value) * 255).rounded())
    }

    private static func percent(_ value: Double) -> Int {
        Int((clamped(value) * 100).rounded())
    }
}

import AppKit
import SwiftUI

/// The design tokens for Settings.
///
/// Deliberately small and near-monochrome: one accent, used only where something is
/// *selected* or *active*, and neutral greys everywhere else with contrast doing the
/// work colour used to.
///
/// Every token resolves per appearance. They were fixed dark values while the window
/// was pinned dark; now that the user picks a theme, a hardcoded `#0B0B0C` would mean
/// white text on a near-black card in light mode.
enum Theme {
    // MARK: Surfaces

    /// Window background.
    static let background = Color(light: 0xF6F6F7, dark: 0x0B0B0C)
    /// Sidebar column, set slightly apart from the content.
    static let sidebar = Color(light: 0xEFEFF1, dark: 0x0E0E0F)
    /// Raised panel: cards, rows, wells.
    static let surface = Color(light: 0xFFFFFF, dark: 0x161617)
    /// Panel under the pointer.
    static let surfaceHover = Color(light: 0xF7F7F8, dark: 0x1C1C1E)
    /// Recessed area inside a panel.
    static let well = Color(light: 0xF2F2F4, dark: 0x101011)

    // MARK: Lines

    static let separator = Color(lightAlpha: 0.10, darkAlpha: 0.07)
    static let separatorStrong = Color(lightAlpha: 0.16, darkAlpha: 0.12)

    // MARK: Ink

    static let text = Color(light: 0x111113, dark: 0xF2F2F2)
    static let textSecondary = Color(light: 0x6B6B70, dark: 0x8C8C90)
    static let textTertiary = Color(light: 0x9A9AA0, dark: 0x5C5C60)

    /// The single accent. If it is on screen, something is on or selected.
    static var accent: Color { .accentColor }

    /// Fill behind a selected sidebar row or a hovered control.
    static let selection = Color(lightAlpha: 0.07, darkAlpha: 0.08)
    static let hover = Color(lightAlpha: 0.04, darkAlpha: 0.04)

    // MARK: Metrics — one 4pt rhythm

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let cardPadding: CGFloat = 20
    static let gap: CGFloat = 10
    /// Gap between one block of content and the next.
    static let sectionGap: CGFloat = 26
    /// Page margin.
    static let margin: CGFloat = 30
}

/// The window background: one flat neutral, no gradient and no glow.
struct SettingsSurface: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}

extension Color {
    /// A colour that resolves per appearance.
    ///
    /// Built on `NSColor`'s dynamic provider rather than reading `\.colorScheme`, so the
    /// value is correct even where it is used outside a `View` body — and so it follows
    /// a window whose appearance is overridden, which is exactly what the theme picker
    /// does.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        })
    }

    /// Ink-on-surface at an alpha, dark in light mode and light in dark mode.
    init(lightAlpha: Double, darkAlpha: Double) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: darkAlpha)
                : NSColor(white: 0, alpha: lightAlpha)
        })
    }

    /// `Color(hex: 0x161617)` — the palette is specified as hex, and spelling each one
    /// as three Doubles buries what it actually is.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// The standard panel: flat fill, hairline, no shadow.
    func panel(radius: CGFloat = Theme.cardRadius, fill: Color = Theme.surface) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            )
    }
}

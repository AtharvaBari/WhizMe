import SwiftUI

/// The single source of layout numbers for every WhizMe screen.
///
/// Misalignment creeps in when each view invents its own padding. Everything that
/// needs an inset, an icon column, or a corner radius reads it from here, so a title
/// in the menu bar, a row in Settings, and a card in onboarding all sit on the same
/// vertical guides.
enum Metrics {
    // MARK: Menu bar panel

    /// Width of the `MenuBarExtra` dropdown.
    static let panelWidth: CGFloat = 300
    /// Gutter between the panel edge and a row's hover background.
    static let panelGutter: CGFloat = 8
    /// Clipboard history is wider than the paste chooser: its rows carry a line of copied
    /// text, and 300pt truncated almost everything worth recognising.
    static let historyPanelWidth: CGFloat = 420
    static let historyPanelHeight: CGFloat = 440
    /// Inset inside a row's hover background.
    static let rowPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 5

    // MARK: Shared

    /// Fixed width reserved for a leading glyph. Every icon is centred in this column,
    /// so titles line up whether their symbol is wide (`rectangle.split.2x2`) or
    /// narrow (`bolt`).
    static let iconColumn: CGFloat = 20
    /// Glyph column → text.
    static let iconGap: CGFloat = 10
    /// Larger glyph column for cards and settings rows.
    static let largeIconColumn: CGFloat = 28

    static let rowCorner: CGFloat = 6
    static let cardCorner: CGFloat = 10

    // MARK: Windows

    static let onboardingWidth: CGFloat = 540
    static let onboardingHeight: CGFloat = 620
    /// Corner radius of the onboarding card. Larger than a system window's 10pt, which
    /// is what makes it read as a purpose-built panel rather than a stock window.
    static let onboardingCorner: CGFloat = 22
    /// Transparent room around the card inside its borderless window.
    ///
    /// The shadow is drawn by SwiftUI rather than AppKit so it scales with the card
    /// during the entrance animation — AppKit's window shadow is computed from opaque
    /// pixels and only refreshes on `invalidateShadow()`, so it visibly lags a scale.
    /// That shadow needs somewhere to land, hence the margin.
    static let onboardingShadowMargin: CGFloat = 46
    static let settingsWidth: CGFloat = 880
    static let settingsHeight: CGFloat = 620
    static let sidebarWidth: CGFloat = 208
    /// Vertical room reserved at the top of the sidebar for the traffic lights, which
    /// float over our content once the title bar is hidden.
    static let trafficLightInset: CGFloat = 42

    // MARK: Settings tiles

    /// Corner radius for the feature tiles on the General page. Larger than a card's,
    /// which is what gives the grid its soft, modern read.
    static let tileCorner: CGFloat = 18
    static let tilePadding: CGFloat = 18
    static let tileGap: CGFloat = 12

    /// Standard content inset for window-sized surfaces.
    static let windowInset: CGFloat = 20
    /// Inset inside a card.
    static let cardPadding: CGFloat = 14
}

extension View {
    /// Places a view in the shared glyph column so every title downstream aligns.
    func iconColumn(_ width: CGFloat = Metrics.iconColumn) -> some View {
        frame(width: width, alignment: .center)
    }
}

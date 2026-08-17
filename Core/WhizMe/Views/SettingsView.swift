import SwiftUI

/// What the sidebar can select.
///
/// Home and Settings are fixed; the categories in between come from the utilities
/// themselves, so adding a utility to a new group grows the sidebar with no view code.
enum SettingsSection: Hashable, Identifiable {
    case home
    case category(FeatureCategory)
    /// The app's own settings — appearance, startup, permissions, about.
    case appSettings

    var id: String {
        switch self {
        case .home: "home"
        case .category(let category): "category.\(category.rawValue)"
        case .appSettings: "settings"
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .category(let category): category.title
        case .appSettings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "square.stack"
        case .category(let category): category.symbolName
        case .appSettings: "gearshape"
        }
    }
}

/// The ⌘, window, built entirely from our own parts.
///
/// No `NavigationSplitView`, no `NavigationStack`, no toolbar: those bring AppKit's
/// sidebar material, its grey selection, its title bar and its chevron. The split is a
/// plain `HStack`, the drill-down is one piece of state, and the chrome is ours.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app

    @State private var section: SettingsSection
    /// The utility being edited, or `nil` at the list. This is the whole navigation
    /// model — one optional.
    @State private var openFeature: WhizFeature?

    init(initialSection: SettingsSection = .home) {
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(section: $section)
            content
        }
        .frame(width: Metrics.settingsWidth, height: Metrics.settingsHeight)
        .background(SettingsSurface())
        .background(SettingsWindowStyler(theme: app.preferences.theme))
        .preferredColorScheme(app.preferences.theme.colorScheme)
        .onAppear { consumePendingRequest() }
        .onChange(of: app.pendingSettingsFeature) { _, _ in consumePendingRequest() }
        .onChange(of: section) { _, _ in
            // Changing section must not leave a utility page from the old one on screen.
            openFeature = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if let feature = openFeature {
                FeatureSettingsRouter(feature: feature, backTitle: section.title) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        openFeature = nil
                    }
                }
                // Slides in from the right and leaves the same way, so the drill-down
                // has a direction the way a real navigation stack does.
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                sectionRoot
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var sectionRoot: some View {
        switch section {
        case .home:
            HomeView(open: openPage)
        case .category(let category):
            CategoryView(category: category, open: openPage)
        case .appSettings:
            AppSettingsView()
        }
    }

    /// Honours a "open Settings at this page" request from the menu bar, then clears
    /// it so re-opening the window later does not jump somewhere unexpected.
    private func consumePendingRequest() {
        guard let feature = app.pendingSettingsFeature else { return }
        app.pendingSettingsFeature = nil
        section = .category(feature.category)
        openFeature = feature
    }

    private func openPage(_ feature: WhizFeature) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            openFeature = feature
        }
    }
}

/// Selects the settings page for a utility. Keeping the mapping in one place means the
/// lists only have to name a feature, not know which view renders it.
private struct FeatureSettingsRouter: View {
    let feature: WhizFeature
    let backTitle: String
    let onBack: () -> Void

    var body: some View {
        switch feature {
        case .awake: AwakeSettingsPage(onBack: onBack)
        case .colorPicker: ColorPickerSettingsPage(onBack: onBack)
        case .textExtractor: TextExtractorSettingsPage(onBack: onBack)
        case .advancedPaste: AdvancedPasteSettingsPage(onBack: onBack)
        case .cleanKeyboard: CleanKeyboardSettingsPage(onBack: onBack)
        case .cleanScreen: CleanScreenSettingsPage(onBack: onBack)
        case .batteryHealth: BatterySettingsPage(onBack: onBack)
        case .clipboardHistory: ClipboardHistorySettingsPage(onBack: onBack)
        case .windowSnapping, .cropAndLock, .workspaces:
            FeatureSettingsScaffold(feature: feature, backTitle: backTitle, onBack: onBack) {
                SettingsCard {
                    SettingsCardRow(
                        symbolName: "hammer",
                        title: "Not built yet",
                        subtitle: feature.subtitle
                    ) {
                        if let badge = feature.availability.badge {
                            RowBadge(text: badge)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment())
}

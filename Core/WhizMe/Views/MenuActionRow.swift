import SwiftUI

/// One line in the menu bar panel: glyph, title, optional detail, optional trailing
/// accessory. Presentation only — every row's behaviour is supplied by the caller so
/// this file never learns what a utility does.
///
/// A row with an `action` becomes a real `Button`, which brings keyboard focus,
/// accessibility, and a pressed state for free. A row without one stays a plain stack,
/// because SwiftUI controls nested inside a button's label never receive clicks — that
/// is how the Awake row keeps a working toggle and duration menu.
struct MenuActionRow<Accessory: View>: View {
    let symbolName: String
    let title: String
    var detail: String?
    var badge: String?
    var isEnabled: Bool = true
    /// Renders the glyph in the secondary colour — for rows that are chrome
    /// (Settings, Quit) rather than utilities.
    var isSecondary: Bool = false
    var action: (() -> Void)?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(MenuRowButtonStyle())
                .disabled(!isEnabled)
        } else {
            content
                .opacity(isEnabled ? 1 : 0.5)
        }
    }

    private var content: some View {
        HStack(spacing: Metrics.iconGap) {
            Image(systemName: symbolName)
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(glyphColor)
                .iconColumn()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    if let badge {
                        MenuRowBadge(text: badge)
                    }
                }

                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            accessory
                .layoutPriority(1)
        }
        .padding(.horizontal, Metrics.rowPadding)
        .padding(.vertical, Metrics.rowVerticalPadding)
        // A floor, not a fixed height: rows with a detail line grow past it, and rows
        // without one still keep the panel's vertical rhythm even.
        .frame(minHeight: 32)
        .contentShape(.rect(cornerRadius: Metrics.rowCorner))
    }

    private var glyphColor: Color {
        guard isEnabled else { return .secondary }
        return isSecondary ? .secondary : .accentColor
    }
}

/// "Soon" / "Pro" marker beside a title.
private struct MenuRowBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(.quaternary, in: Capsule())
    }
}

/// Hover and pressed fills that read correctly in both appearances.
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowSurface(configuration: configuration)
    }

    // Nested view so `@State` for hover actually participates in the view graph —
    // a ButtonStyle's makeBody is not itself a View.
    private struct RowSurface: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: Metrics.rowCorner, style: .continuous)
                        .fill(fill)
                }
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { isHovering = $0 && isEnabled }
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }

        private var fill: AnyShapeStyle {
            if configuration.isPressed {
                AnyShapeStyle(.tertiary)
            } else if isHovering {
                AnyShapeStyle(.quaternary)
            } else {
                AnyShapeStyle(.clear)
            }
        }
    }
}

extension MenuActionRow where Accessory == EmptyView {
    init(
        symbolName: String,
        title: String,
        detail: String? = nil,
        badge: String? = nil,
        isEnabled: Bool = true,
        isSecondary: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            symbolName: symbolName,
            title: title,
            detail: detail,
            badge: badge,
            isEnabled: isEnabled,
            isSecondary: isSecondary,
            action: action,
            accessory: { EmptyView() }
        )
    }
}

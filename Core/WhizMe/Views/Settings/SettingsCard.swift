import SwiftUI

/// A titled group of rows — our replacement for `Form`'s grouped `Section`.
///
/// `formStyle(.grouped)` renders AppKit's own inset table, which brings its own greys,
/// insets and typography and looks nothing like the rest of this window. This draws the
/// same idea on our own surface, so a settings page and the tile grid share one visual
/// language.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 2)
            }

            VStack(spacing: 0) {
                content
            }
            .panel()

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            }
        }
    }
}

/// One row inside a `SettingsCard`: glyph, title, optional subtitle, trailing control.
/// Every row shares the same glyph column, which is what keeps titles on one guide.
struct SettingsCardRow<Trailing: View>: View {
    let symbolName: String
    let title: String
    var subtitle: String?
    var tint: Color = .accentColor
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            trailing
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

extension SettingsCardRow where Trailing == EmptyView {
    init(symbolName: String, title: String, subtitle: String? = nil, tint: Color = .accentColor) {
        self.init(symbolName: symbolName, title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

/// Hairline between rows, inset to start at the text column.
struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.leading, 50)
    }
}

import SwiftUI

/// One row inside a Settings form: glyph, title, optional subtitle, trailing control.
///
/// Every section in Settings builds its rows from this, which is what keeps titles on
/// a single vertical guide whether the row carries a switch, a picker, a shortcut, or
/// a button. Rows that skipped the glyph used to start ~34pt to the left of the ones
/// that had it.
struct SettingsRow<Trailing: View>: View {
    let symbolName: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .medium))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            trailing
                .layoutPriority(1)
        }
        .padding(.vertical, 5)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(symbolName: String, title: String, subtitle: String? = nil) {
        self.init(symbolName: symbolName, title: title, subtitle: subtitle) { EmptyView() }
    }
}

import SwiftUI

/// One utility as a list row, used by Home and by each category page.
///
/// The whole row opens the utility's page; the switch is a *sibling* of that button
/// rather than a child, because SwiftUI controls nested inside a button's label never
/// receive clicks.
struct FeatureRow: View {
    let feature: WhizFeature
    /// One short line of live state — a shortcut, a countdown, a blocker.
    let status: String
    /// Draws the status in the accent when something is running or needs attention.
    var isHighlighted: Bool = false
    /// Marks the most recently added utility on the Home list.
    var isNew: Bool = false
    @Binding var isOn: Bool
    let open: () -> Void

    @State private var isHovering = false

    private var isAvailable: Bool { feature.availability == .shipping }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: open) {
                HStack(spacing: 14) {
                    Image(systemName: feature.symbolName)
                        .font(.system(size: 15))
                        .foregroundStyle((isOn || feature.isOnDemand) && isAvailable ? Theme.accent : Theme.textTertiary)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text(feature.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.text)

                            if isNew {
                                RowBadge(text: "New", isAccent: true)
                            } else if let badge = feature.availability.badge {
                                RowBadge(text: badge)
                            }
                        }

                        Text(feature.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isHighlighted ? Theme.accent : Theme.textTertiary)
                        .lineLimit(1)
                        // Clears whatever is parked on the trailing edge.
                        .padding(.trailing, feature.isOnDemand ? 34 : 52)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isAvailable ? 1 : 0.55)

            // On-demand utilities have no switch: they are started from their own page.
            if !feature.isOnDemand {
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(!isAvailable)
                    .padding(.trailing, 16)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.trailing, 18)
            }
        }
        .background(isHovering ? Theme.hover : .clear)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityLabel("\(feature.title) settings")
    }
}

/// "New", "Soon", "Pro".
struct RowBadge: View {
    let text: String
    var isAccent: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(isAccent ? Theme.accent : Theme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(isAccent ? Theme.accent.opacity(0.14) : Theme.selection)
            )
    }
}

import SwiftUI

/// WhizMe's own sidebar — not `NavigationSplitView`'s.
///
/// Two destinations: the list of utilities, and the app's own settings.
///
/// There used to be five category pages between them. They listed the same utilities Home
/// already lists and led to the same pages, so every utility was reachable two ways — and
/// one category ("Windows") held nothing but unbuilt features, making it a sidebar entry
/// that led nowhere. Eight utilities do not need a taxonomy.
struct SettingsSidebar: View {
    @Binding var section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand

            VStack(spacing: 2) {
                item(.home)
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)

            item(.appSettings)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
        .frame(width: Metrics.sidebarWidth)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1)
        }
    }

    private func item(_ target: SettingsSection) -> some View {
        SidebarItem(
            title: target.title,
            symbolName: target.icon,
            isSelected: section == target
        ) {
            section = target
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(AppInfo.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        // Clears the traffic lights, which float over our own content.
        .padding(.top, Metrics.trafficLightInset)
        .padding(.bottom, 22)
    }
}

/// One sidebar row.
private struct SidebarItem: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(fill)
            }
            .contentShape(.rect(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var fill: Color {
        if isSelected { return Theme.selection }
        return isHovering ? Theme.hover : .clear
    }
}

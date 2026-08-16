import SwiftUI

/// Live status capsule for a TCC permission — green once granted, orange while
/// outstanding. Shared by onboarding and Settings so the same state never renders two
/// different ways.
struct PermissionStatusBadge: View {
    let state: PermissionState

    var body: some View {
        Label {
            Text(state.label)
        } icon: {
            Image(systemName: state.symbolName)
                .symbolRenderingMode(.hierarchical)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.22)))
        .fixedSize()
    }

    private var tint: Color {
        state.isGranted ? .green : .orange
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        PermissionStatusBadge(state: .granted)
        PermissionStatusBadge(state: .denied)
        PermissionStatusBadge(state: .unknown)
    }
    .padding()
}

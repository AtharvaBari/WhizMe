import SwiftUI

/// Shown while the keyboard is disabled for cleaning.
///
/// Deliberately covers the screen. It states plainly that the keyboard is off and gives
/// the one way back — a button, because the trackpad is the only input still working.
/// Without it, a disabled keyboard and no visible explanation is indistinguishable from
/// a hung Mac.
struct CleanKeyboardOverlay: View {
    let onFinish: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)

            VStack(spacing: 0) {
                Image(systemName: "keyboard")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating)

                Text("Keyboard is off")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .tracking(-0.6)
                    .padding(.top, 26)

                Text("Wipe away — nothing you press will register.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 8)

                Button(action: onFinish) {
                    HStack(spacing: 9) {
                        Image(systemName: "cursorarrow.rays")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Re-enable keyboard")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .padding(.top, 34)

                Text("Use the trackpad — the keyboard cannot dismiss this.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 14)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96)
        }
        .ignoresSafeArea()
        .task {
            withAnimation(.easeOut(duration: 0.28)) { appeared = true }
        }
    }
}

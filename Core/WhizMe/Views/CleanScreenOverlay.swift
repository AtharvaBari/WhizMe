import SwiftUI

/// A black sheet over every display, so the screen can be wiped without setting
/// anything off.
///
/// The hint fades out after a few seconds rather than staying put: a permanently lit
/// caption is exactly the bright patch you were trying to get rid of. It comes back on
/// mouse movement, so the way out is never lost for good.
struct CleanScreenOverlay: View {
    @State private var showsHint = true

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 10) {
                Text("Screen is off for cleaning")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                Text("Press Esc or Return to bring it back")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.32))
            }
            .opacity(showsHint ? 1 : 0)
        }
        .ignoresSafeArea()
        .onContinuousHover { phase in
            // Moving the pointer brings the way out back, then it fades again.
            if case .active = phase { revealHint() }
        }
        .task {
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.easeInOut(duration: 1.2)) { showsHint = false }
        }
    }

    private func revealHint() {
        guard !showsHint else { return }
        withAnimation(.easeOut(duration: 0.25)) { showsHint = true }

        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 1.2)) { showsHint = false }
        }
    }
}

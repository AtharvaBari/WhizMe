import SwiftUI

/// Entrance/exit phase of the onboarding window, owned by `OnboardingPresenter`.
///
/// A reference type rather than `@State` inside the chrome because the presenter has to
/// *drive* the exit: it needs the card to visibly leave before the window closes, and
/// the close itself is AppKit's job, not the view's. Keeping the phase here also keeps
/// `OnboardingWindowChrome` pixels-only, per the layering rules.
@MainActor
@Observable
final class OnboardingChromeState {
    /// Set on appear to trigger the entrance.
    var isPresented = false
    /// Set by the presenter when the exit begins.
    var isClosing = false

    /// Long enough that the card has visibly gone before the window disappears, short
    /// enough that dismissing never feels like waiting. Shared with the exit spring so
    /// the two cannot drift apart.
    static let exitDuration: TimeInterval = 0.22
}

/// The onboarding window's own chrome: a rounded, shadowed card floating in a
/// transparent borderless window.
///
/// Onboarding is the first thing anyone sees, and a stock titled window — traffic
/// lights, an empty title bar — makes it look like a settings dialog that opened by
/// accident. Drawing the panel ourselves gives up three things AppKit provided for
/// free (dragging, closing, the shadow), so each is handled explicitly: dragging by
/// `isMovableByWindowBackground`, closing by Escape and the button below, and the
/// shadow here.
///
/// ## Why the shadow is ours and not AppKit's
///
/// `NSWindow.hasShadow` derives its shape from the window's opaque pixels and only
/// recomputes on `invalidateShadow()`. During the scale-in that leaves the shadow a
/// frame or two behind the card, which reads as the panel sliding out of its own
/// shadow. A SwiftUI shadow is part of the same render pass, so it scales in lockstep.
struct OnboardingWindowChrome<Content: View>: View {
    let state: OnboardingChromeState
    @ViewBuilder var content: Content

    @Environment(\.dismissOnboarding) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var closeButtonHovered = false

    var body: some View {
        card
            .frame(width: Metrics.onboardingWidth, height: Metrics.onboardingHeight)
            .scaleEffect(scale)
            .opacity(state.isPresented && !state.isClosing ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                guard !reduceMotion else {
                    state.isPresented = true
                    return
                }
                // Nearly critically damped. A window the user did not throw should not
                // bounce — overshoot on something that merely appeared reads as a
                // gimmick — but a whisper of settle keeps it from being a hard cut.
                withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                    state.isPresented = true
                }
            }
    }

    /// Grows in from slightly small, and *shrinks* on the way out rather than reversing
    /// the entrance: pulling away reads as dismissal, where swelling past full size
    /// reads as another attempt to open.
    private var scale: CGFloat {
        if state.isClosing { return 0.965 }
        return state.isPresented ? 1 : 0.94
    }

    private var card: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Metrics.onboardingCorner, style: .continuous))
            .overlay(alignment: .topTrailing) { closeButton }
            .overlay {
                // A single hairline, brighter at the top. Without it the card's edge
                // dissolves into a dark desktop and the corners lose their definition.
                RoundedRectangle(cornerRadius: Metrics.onboardingCorner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            // Two shadows, not one: a tight dark contact shadow anchors the card to the
            // desktop, a wide soft one gives it height. One radius has to choose between
            // those and gets neither.
            .shadow(color: .black.opacity(0.34), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
    }

    /// The third way out, after Skip and Done — so it stays quiet until pointed at.
    private var closeButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(closeButtonHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 22, height: 22)
                .background {
                    Circle()
                        .fill(.quaternary)
                        .opacity(closeButtonHovered ? 1 : 0)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(14)
        .help("Close")
        // Fast, because feedback that waits is what makes an interface feel dead.
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { closeButtonHovered = hovering }
        }
    }
}

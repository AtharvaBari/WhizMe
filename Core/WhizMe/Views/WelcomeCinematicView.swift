import AppKit
import SwiftUI

/// The first-launch welcome: the desktop dims, the logo assembles itself from particles
/// in the middle of the screen, slides left to make room, and the wordmark slides out
/// from behind it. A Continue button arrives once the sequence has finished.
///
/// Reuses `LogoAssembleView` at cinema scale rather than reimplementing the particle
/// work — it already draws every tile in one `Canvas` and drops the canvas the moment it
/// settles, which is what keeps 400 tiles from stuttering.
///
/// ## Timing
///
/// The whole sequence is one script rather than a chain of `onAppear`/`onChange`
/// handlers, so the order is readable in one place and cannot drift. Escape or Continue
/// end it at any point — nothing here locks the user in.
struct WelcomeCinematicView: View {
    /// Called when the user is done with the welcome, by either route.
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .waiting
    /// Fixed when the assemble begins so the particle clock and this view agree.
    @State private var assembleStart = Date()

    /// Ordered, and compared with `>=` — so "has the logo split yet" is one check
    /// rather than a list of cases to keep in sync.
    private enum Phase: Int, Comparable {
        case waiting, dimmed, assembling, split, ready

        static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: Layout

    /// Big enough to read as a title card on a laptop display without overflowing one.
    private static let iconSize: CGFloat = 260
    private static let titleSize: CGFloat = 92
    /// Space between the settled logo and the wordmark.
    private static let gap: CGFloat = 34

    /// Space Mono Bold, bundled in `Resources/Fonts` and registered by
    /// `ATSApplicationFontsPath` in Info.plist.
    ///
    /// Falls back to the system face if registration ever fails. That is not
    /// hypothetical: a missing custom font does not raise anything, it silently
    /// substitutes — so the fallback is here to keep the *measurement* below honest
    /// rather than to be pretty.
    private static let titleNSFont: NSFont =
        NSFont(name: "SpaceMono-Bold", size: titleSize)
            ?? .systemFont(ofSize: titleSize, weight: .bold)

    /// One font object drives both the measurement and the rendering, so the two can
    /// never disagree — if they did, the slide would stop and leave the wordmark a few
    /// points off centre.
    private static let titleFont = Font(titleNSFont)

    /// Measured with AppKit rather than a `GeometryReader` pass.
    ///
    /// The offsets below have to be known in the same frame the slide starts, and a
    /// geometry read only lands on the *next* one — which showed as the wordmark
    /// snapping into position after the first frame of its own animation.
    private static let titleWidth: CGFloat =
        ("WhizMe" as NSString).size(withAttributes: [.font: titleNSFont]).width

    /// Where the logo sits once it has made room for the wordmark: half the wordmark
    /// block to the left, so logo and text together end up centred.
    private var logoOffsetX: CGFloat {
        phase >= .split ? -(Self.gap + Self.titleWidth) / 2 : 0
    }

    var body: some View {
        ZStack {
            backdrop

            // The wordmark is *behind* the logo in z-order, which is what lets it slide
            // out from underneath rather than appearing beside it.
            wordmark
            logo

            continueButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Escape is handled by the window; this covers a click anywhere once the
        // sequence is over, which is what people try after a title card.
        .onTapGesture {
            if phase == .ready { onContinue() }
        }
        .task { await run() }
    }

    // MARK: Sequence

    private func run() async {
        guard !reduceMotion else {
            // No particles, no slide, no stagger — everything arrives at once behind a
            // short fade. Skipping straight to `.ready` also skips `LogoAssembleView`,
            // which draws its settled artwork directly under reduced motion.
            assembleStart = .now
            withAnimation(.easeOut(duration: 0.25)) { phase = .ready }
            return
        }

        withAnimation(.easeOut(duration: 0.55)) { phase = .dimmed }

        // Let the dim land before anything is drawn on top of it, or the particles
        // start against a half-lit desktop and read as a glitch.
        try? await Task.sleep(for: .seconds(0.4))
        assembleStart = .now
        phase = .assembling

        // The particle assembly runs on its own wall clock, so wait it out rather than
        // guessing. The extra beat lets it visibly settle before it moves again.
        try? await Task.sleep(for: .seconds(LogoAssembleView.duration + 0.22))
        // Slower and softer than a UI spring: this is a camera move, not a control
        // responding to a press.
        withAnimation(.spring(response: 0.78, dampingFraction: 0.86)) { phase = .split }

        try? await Task.sleep(for: .seconds(0.72))
        // The one place a bounce is earned — an arrival beat at the end of a sequence
        // that has been entirely smooth until now.
        withAnimation(.spring(response: 0.46, dampingFraction: 0.66)) { phase = .ready }
    }

    // MARK: Pieces

    /// Darkens the desktop without hiding it: the app is announcing itself over the
    /// user's Mac, not replacing it.
    private var backdrop: some View {
        Color.black
            .opacity(phase >= .dimmed ? 0.82 : 0)
            .ignoresSafeArea()
    }

    private var logo: some View {
        Group {
            if phase >= .assembling {
                LogoAssembleView(startDate: assembleStart, size: Self.iconSize)
            } else {
                // Holds the slot so the assembly does not shift the layout when it
                // appears — its canvas is far larger than the logo itself.
                Color.clear.frame(width: Self.iconSize, height: Self.iconSize)
            }
        }
        .offset(x: logoOffsetX)
    }

    /// Slides out from behind the logo, left to right, fading in as it goes.
    ///
    /// Clipped to a window whose left edge sits exactly on the logo's trailing edge, so
    /// the text is revealed *by* the logo's edge. Relying on z-order alone would not
    /// work: the wordmark is wider than the logo, so its ends would stick out either
    /// side before it ever moved.
    private var wordmark: some View {
        // The outer frame is the reveal window; the text slides inside it. Its width is
        // the gap plus the wordmark, so at the start offset the text sits entirely to
        // the left of the window and is clipped away completely.
        ZStack(alignment: .leading) {
            Text("WhizMe")
                .font(Self.titleFont)
                .foregroundStyle(.white)
                .fixedSize()
                .padding(.leading, Self.gap)
                .offset(x: phase >= .split ? 0 : -(Self.gap + Self.titleWidth))
        }
        // Generous height so ascenders and descenders are never shaved by the clip.
        .frame(width: Self.gap + Self.titleWidth, height: Self.titleSize * 1.8, alignment: .leading)
        .clipped()
        .opacity(phase >= .split ? 1 : 0)
        // Half a logo to the right of centre puts this window's left edge exactly on the
        // logo's trailing edge, so the logo itself is what uncovers the text.
        .offset(x: Self.iconSize / 2)
    }

    private var continueButton: some View {
        VStack {
            Spacer()

            // Two things here are deliberate, both worked out by tracing a welcome that
            // dismissed itself the moment the sequence ended:
            //
            // 1. NO `.keyboardShortcut(.defaultAction)`. In a borderless key window that
            //    fires the button's action on its own, with no click. Return is handled
            //    by `CinematicWindow` instead, where it is explicit.
            // 2. Inserted at `.ready` rather than held `.disabled` and faded in. A
            //    `Button` whose `disabled` flips true→false also self-fires.
            if phase >= .ready {
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    // The one place a bounce is earned: an arrival beat closing a
                    // sequence that has been smooth throughout.
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .padding(.bottom, 96)
            }
        }
    }
}

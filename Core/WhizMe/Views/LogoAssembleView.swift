import SwiftUI

/// The intro flourish: the logo's tiles swirl in from around the window and settle into
/// place from the centre outward, then resolve into the real artwork.
///
/// Drawn in a single `Canvas` rather than one `Image` per tile. The view-per-tile
/// approach meant 676 full-size images in the hierarchy, each one clipped down to a
/// ~7pt square — SwiftUI had to lay out, composite, and animate all of them every
/// frame, which is what made the motion stutter no matter how the curve was tuned.
/// Here every tile is a handful of arithmetic and one clipped draw of a single resolved
/// image, and once the animation is over the canvas is dropped entirely.
struct LogoAssembleView: View {
    /// When the sequence began. Progress is derived from wall-clock time rather than
    /// SwiftUI's animation system, so the motion is frame-accurate.
    let startDate: Date
    var size: CGFloat = 200

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isComplete = false

    /// 20×20 divides a 200pt logo into exact 10pt tiles. Fractional tile sizes leave
    /// hairline seams between the clipped pieces.
    private let grid = 20
    /// How long one tile takes once its turn arrives.
    private let tileDuration: TimeInterval = 0.85
    /// Spread of the per-tile head start.
    private let maxDelay: TimeInterval = 0.5

    /// Total run time, including the resolve into the real artwork at the end.
    static let duration: TimeInterval = 1.7
    static let reducedMotionDuration: TimeInterval = 0.45

    /// Room around the logo for tiles to fly in from. Without it the canvas clips them
    /// and they appear to pop out of the edges instead of travelling.
    private var canvasSide: CGFloat { size * 2.3 }

    var body: some View {
        Group {
            if reduceMotion {
                settledLogo
            } else if isComplete {
                // Nothing left to animate — drop the canvas so an onboarding window
                // left open is not redrawing 400 tiles forever.
                settledLogo
            } else {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    let resolve = resolveAmount(elapsed)

                    ZStack {
                        Canvas { context, _ in
                            draw(&context, elapsed: elapsed)
                        }
                        .frame(width: canvasSide, height: canvasSide)
                        .opacity(1 - resolve)

                        // Crossfading to the real artwork inside the same timeline is
                        // what keeps the corners from popping from square to rounded.
                        settledLogo
                            .opacity(resolve)
                            .scaleEffect(0.985 + 0.015 * resolve)
                    }
                }
            }
        }
        .frame(width: canvasSide, height: canvasSide)
        .task {
            let wait = reduceMotion ? Self.reducedMotionDuration : Self.duration
            try? await Task.sleep(for: .seconds(wait))
            isComplete = true
        }
    }

    private var settledLogo: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: size * 0.12, y: size * 0.05)
    }

    // MARK: - Drawing

    private func draw(_ context: inout GraphicsContext, elapsed: TimeInterval) {
        let resolved = context.resolve(Image("Logo"))
        let tile = size / CGFloat(grid)
        let origin = CGPoint(x: (canvasSide - size) / 2, y: (canvasSide - size) / 2)
        let logoRect = CGRect(origin: origin, size: CGSize(width: size, height: size))
        let centre = CGPoint(x: canvasSide / 2, y: canvasSide / 2)
        // Longest distance from the middle, used to normalise the stagger.
        let maxRadius = (size / 2) * 1.4142

        for row in 0..<grid {
            for col in 0..<grid {
                let index = row * grid + col

                let home = CGRect(
                    x: origin.x + CGFloat(col) * tile,
                    y: origin.y + CGFloat(row) * tile,
                    width: tile,
                    height: tile
                )
                let homeCentre = CGPoint(x: home.midX, y: home.midY)

                // Assemble from the middle outward, with a little jitter so the wave
                // reads as organic rather than as a expanding ring.
                let radius = hypot(homeCentre.x - centre.x, homeCentre.y - centre.y)
                let delay = (radius / maxRadius) * maxDelay * 0.8
                    + noise(index, 1) * maxDelay * 0.25

                let t = (elapsed - delay) / tileDuration
                guard t > 0 else { continue }
                let progress = min(1, t)

                let settle = easeOutBack(progress)
                let spin = easeOutCubic(progress)
                let alpha = min(1, progress * 3)

                // Start scattered on a ring around the logo, close enough to stay on
                // screen so the travel is actually visible.
                let angle = noise(index, 2) * 2 * .pi
                let distance = size * (0.55 + noise(index, 3) * 0.6)
                let remaining = 1 - settle
                let current = CGPoint(
                    x: homeCentre.x + cos(angle) * distance * remaining,
                    y: homeCentre.y + sin(angle) * distance * remaining
                )

                let startAngle = (noise(index, 4) - 0.5) * 420
                let startScale = 0.25 + noise(index, 5) * 0.2
                let scale = startScale + (1 - startScale) * settle

                var tileContext = context
                tileContext.opacity = alpha
                tileContext.translateBy(x: current.x, y: current.y)
                tileContext.rotate(by: .degrees(startAngle * (1 - spin)))
                tileContext.scaleBy(x: scale, y: scale)
                tileContext.translateBy(x: -homeCentre.x, y: -homeCentre.y)
                // Half a point of overlap hides the seams between neighbouring tiles.
                tileContext.clip(to: Path(home.insetBy(dx: -0.5, dy: -0.5)))
                tileContext.draw(resolved, in: logoRect)
            }
        }
    }

    /// Crossfade from the assembled tiles to the real artwork over the last stretch.
    private func resolveAmount(_ elapsed: TimeInterval) -> Double {
        let start = Self.duration - 0.32
        guard elapsed > start else { return 0 }
        return min(1, (elapsed - start) / 0.32)
    }

    // MARK: - Curves

    /// Overshoots slightly past the target and settles back — the bit that reads as
    /// playful rather than mechanical.
    private func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        let p = t - 1
        return 1 + c3 * p * p * p + c1 * p * p
    }

    private func easeOutCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    /// Deterministic per-tile randomness.
    ///
    /// The previous version called `Double.random` inside `body`, so every re-render
    /// produced new targets and the tiles visibly jittered as they flew. Hashing the
    /// index instead means a tile's path is fixed for the life of the animation.
    private func noise(_ index: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: index &* 73_856_093 &+ salt &* 19_349_663 &+ 0x9E37_79B9)
        x ^= x >> 33
        x = x &* 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        x = x &* 0xc4ce_b9fe_1a85_ec53
        x ^= x >> 33
        return Double(x % 100_000) / 100_000.0
    }
}

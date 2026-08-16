import AppKit
import os

/// Async wrapper over `NSColorSampler`, the system eyedropper.
///
/// Nothing else here: no history, no clipboard, no banners. Callers get one
/// `SampledColor` or `nil` and decide what that means.
@MainActor
enum ColorSamplerService {
    /// Shows the system eyedropper and waits for the user to click a pixel.
    /// - Returns: The sampled color in sRGB, or `nil` if the user cancelled with
    ///   Escape (or the color could not be converted to sRGB).
    static func sample() async -> SampledColor? {
        // WhizMe is an accessory (menu bar) app, so it is usually not the active
        // application when a global shortcut fires. Without this the sampler can
        // come up behind the frontmost app and never take over the cursor.
        NSApp.activate()

        return await withCheckedContinuation { continuation in
            ColorSamplingSession(continuation: continuation).start()
        }
    }
}

/// Owns exactly one sampling session.
///
/// Two things make this a type rather than a few lines inside `sample()`:
///
/// 1. `NSColorSampler` must stay alive until its handler fires. A local that goes
///    out of scope at the end of `sample()` is released mid-session, the handler
///    never runs, and the continuation leaks forever — the task simply never
///    resumes. The session holds the sampler; the handler holds the session.
/// 2. The handler is imported as `@Sendable`, which cannot capture a non-Sendable
///    `NSColorSampler` directly. A `@MainActor` class *is* `Sendable`, so the
///    handler captures this instead and reaches the sampler through it.
@MainActor
private final class ColorSamplingSession {
    private var sampler: NSColorSampler?
    private var continuation: CheckedContinuation<SampledColor?, Never>?
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "ColorSampler")

    init(continuation: CheckedContinuation<SampledColor?, Never>) {
        self.continuation = continuation
    }

    func start() {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { color in
            // AppKit documents this handler as being called on the main thread, but
            // the ObjC block is unannotated and therefore imported as `@Sendable`,
            // so the compiler cannot see that guarantee. `assumeIsolated` asserts
            // the documented contract instead of hopping and losing the frame.
            MainActor.assumeIsolated {
                self.finish(with: color)
            }
        }
    }

    /// Resumes the continuation exactly once and releases the sampler.
    private func finish(with color: NSColor?) {
        // Dropping the sampler here also breaks the sampler -> handler -> session
        // -> sampler cycle that keeps everything alive during the session.
        sampler = nil

        guard let continuation else { return } // Defensive: a second call is inert.
        self.continuation = nil

        guard let color else {
            log.debug("Color sampling cancelled")
            continuation.resume(returning: nil)
            return
        }

        guard let sampled = SampledColor(nsColor: color) else {
            log.error("Sampled color could not be converted to sRGB")
            continuation.resume(returning: nil)
            return
        }

        continuation.resume(returning: sampled)
    }
}

private extension SampledColor {
    /// Bridges AppKit's color into the pure-data model.
    ///
    /// The conversion is mandatory, not cosmetic: the sampler returns colors in the
    /// sampled display's native space, and reading `redComponent` on a color whose
    /// space is not RGB-based traps at runtime. Returning `nil` on a failed
    /// conversion loses a sample; reading the components blind loses the app.
    init?(nsColor: NSColor) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: srgb.redComponent,
            green: srgb.greenComponent,
            blue: srgb.blueComponent,
            alpha: srgb.alphaComponent
        )
    }
}

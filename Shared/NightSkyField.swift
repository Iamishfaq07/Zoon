import Foundation

/// The star field's geometry and its redraw policy, separated from the view
/// that draws it.
///
/// Two reasons, one practical and one architectural. The policy — how often a
/// sky may redraw, how many of its stars move — is a decision about battery
/// and attention, not about rendering, and it is the part worth testing. And
/// a view file in the app target is not compiled into the test target, so
/// anything left inside `NightSky` could not be asserted on at all.
enum NightSkyField {

    /// How hard an instance is allowed to work.
    ///
    /// Almost every use is background texture behind something the reader is
    /// actually looking at, and texture does not deserve a
    /// twelve-frame-a-second full-canvas redraw for the life of the screen.
    /// `immersive` is for the two places the sky *is* the content: onboarding
    /// and the splash.
    enum Presence: Sendable, CaseIterable {
        case ambient
        case immersive

        /// Seconds between redraws.
        var interval: Double {
            switch self {
            case .ambient: 1 / 3
            case .immersive: 1 / 12
            }
        }

        /// One star in this many twinkles; the rest are drawn and left alone.
        /// A sky where every star pulses together reads as a flicker rather
        /// than as a sky, and costs the most to produce.
        var twinklingEvery: Int {
            switch self {
            case .ambient: 4
            case .immersive: 1
            }
        }
    }

    struct Star: Sendable, Hashable {
        let u: Double, v: Double
        let depth: Double
        let radius: Double
        let phase: Double
        let speed: Double
        let twinkles: Bool
    }

    /// Deterministic, so the same screen draws the same sky every time rather
    /// than reshuffling whenever state changes.
    ///
    /// Built when the view's `body` runs, not inside the canvas closure. The
    /// previous version recomputed 56 positions, depths and radii twelve times
    /// a second in order to animate one opacity each — `body` runs on state
    /// changes, the canvas closure runs every frame, and that was the cost.
    static func stars(count: Int, twinklingEvery: Int) -> [Star] {
        (0..<max(0, count)).map { i in
            let u = frac(Double(i) * 0.6180339887)
            return Star(
                u: u,
                v: frac(Double(i) * 0.4142135623),
                depth: 0.35 + frac(Double(i) * 0.27) * 0.85,
                radius: 0.7 + 1.7 * frac(Double(i) * 0.19),
                phase: Double(i),
                speed: 0.32 + u,
                twinkles: twinklingEvery <= 1 || i % twinklingEvery == 0
            )
        }
    }

    static func frac(_ x: Double) -> Double { x - floor(x) }
}

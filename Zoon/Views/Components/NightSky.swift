import SwiftUI

/// A quiet star field. Parallax is for a drag; twinkle is for waiting.
/// Reduced Motion freezes both — the stars stay, they just stop moving.
struct NightSky: View {
    var parallax: CGSize = .zero
    var starCount: Int = 56
    /// See `NightSkyField.Presence`. Ambient by default: most uses are
    /// texture behind content, not the content.
    var presence: NightSkyField.Presence = .ambient

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Motion stops when it cannot be seen or cannot be afforded.
    ///
    /// Reduce Motion was already honoured. A backgrounded scene and Low Power
    /// Mode were not: the timeline kept ticking behind the app switcher, and
    /// kept ticking on a phone whose owner had explicitly asked it to
    /// conserve.
    private var isPaused: Bool {
        reduceMotion
            || scenePhase != .active
            || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        let stars = NightSkyField.stars(
            count: starCount, twinklingEvery: presence.twinklingEvery
        )
        TimelineView(.animation(minimumInterval: presence.interval, paused: isPaused)) { timeline in
            Canvas { context, size in
                let t = isPaused ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
                for star in stars {
                    let x = star.u * size.width + parallax.width * star.depth
                    let y = star.v * size.height + parallax.height * star.depth
                    let twinkle = (isPaused || !star.twinkles)
                        ? 0.62
                        : 0.32 + 0.68 * abs(sin(t * star.speed + star.phase))
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: star.radius, height: star.radius)),
                        with: .color(Color.white.opacity(twinkle * 0.9))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Waxing crescent that follows a drag. Used on first-run, not as decoration
/// on every screen — a permanent pulse here was previously rejected because
/// it explained nothing. Drag is the explanation: this is the moon.
struct InteractiveMoon: View {
    var size: CGFloat = 220

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGSize = .zero
    @State private var settled = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.Family.Moon.lit.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: size * 0.58
                    )
                )
                .frame(width: size, height: size)
                .scaleEffect(settled || reduceMotion ? 1 : 0.9)

            // The same moon the week strip draws, so the hero and the history
            // are recognisably the same object -- and here, the one place it
            // is the focal point rather than a datum, it turns.
            MoonCycle(size: size * 0.78, active: true)
        }
        .offset(x: drag.width * 0.14, y: drag.height * 0.14)
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { _ in
                    // The spring back was unguarded: with Reduce Motion on,
                    // the parallax itself is suppressed but letting go still
                    // sprang.
                    withAnimation(Motion.respecting(reduceMotion, Motion.hero)) { drag = .zero }
                }
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.hero) { settled = true }
        }
        .accessibilityHidden(true)
    }
}

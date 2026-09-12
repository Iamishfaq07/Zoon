import SwiftUI

/// A quiet star field. Parallax is for a drag; twinkle is for waiting.
/// Reduced Motion freezes both — the stars stay, they just stop moving.
struct NightSky: View {
    var parallax: CGSize = .zero
    var starCount: Int = 56

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 10 : 1 / 12, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<starCount {
                    let u = Self.frac(Double(i) * 0.6180339887)
                    let v = Self.frac(Double(i) * 0.4142135623)
                    let depth = 0.35 + Self.frac(Double(i) * 0.27) * 0.85
                    let x = u * size.width + parallax.width * depth
                    let y = v * size.height + parallax.height * depth
                    let twinkle = reduceMotion
                        ? 0.62
                        : 0.32 + 0.68 * abs(sin(t * (0.32 + u) + Double(i)))
                    let r = 0.7 + 1.7 * Self.frac(Double(i) * 0.19)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                        with: .color(Color.white.opacity(twinkle * 0.9))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func frac(_ x: Double) -> Double {
        x - floor(x)
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
                    withAnimation(Motion.hero) { drag = .zero }
                }
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.hero) { settled = true }
        }
        .accessibilityHidden(true)
    }
}

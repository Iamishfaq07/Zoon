import SwiftUI

/// The moon, drawn rather than borrowed from SF Symbols.
///
/// In `Shared/` so the app, both widget extensions and the watch all draw the
/// *same* moon. `moonphase.waxing.crescent` was used in ten places across
/// those targets and is not a moon: its unlit half is a filled slab, so under
/// `.hierarchical` rendering it reads as a grey-and-white split sphere.
///
/// Depends on nothing but SwiftUI and `Theme.Family.Moon`/`.sleep`, which is
/// what makes it portable to every target.

/// Waxing moon whose illumination is asleep ÷ need.
struct MoonFill: View {
    var fill: Double
    var active: Bool
    var size: CGFloat = 28
    /// Lit from the west, as the moon is on its way to full. Waning lights the
    /// other limb — the surface never mirrors, only the sun moves.
    var waxing: Bool = true

    var body: some View {
        Canvas { context, canvasSize in
            drawMoon(
                in: &context, canvasSize: canvasSize,
                fill: fill, waxing: waxing, active: active
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The moon, turning.
///
/// A full synodic cycle — new, waxing crescent, first quarter, gibbous, full,
/// then back down the other limb — compressed into `period` seconds. The
/// surface stays put and the terminator sweeps across it, which is what makes
/// it read as one object being lit rather than a shape changing shape.
///
/// `TimelineView(.animation)` rather than an animated parameter: the phase is
/// drawn inside a `Canvas`, and SwiftUI cannot interpolate a Canvas. Driving
/// it from the timeline redraws each frame, which is the supported way to
/// animate one.
struct MoonCycle: View {
    var size: CGFloat = 168
    /// Seconds for one full cycle. Slow on purpose: the moon is not a spinner,
    /// and anything brisk enough to notice becomes something to watch instead
    /// of something to glance at.
    var period: Double = 48
    var active: Bool = true
    /// Where it rests when the viewer has asked for less motion.
    var restingFill: Double = 0.34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            // Not a paused animation: a still moon, at a phase worth showing.
            MoonFill(fill: restingFill, active: active, size: size)
        } else {
            // 20fps, not 60. The cycle takes 48 seconds, so a frame every
            // 50ms is already finer than the eye can resolve here, and the
            // moon is around a hundred fills a frame -- three times the work
            // for motion nobody can see is a battery cost with no payoff.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                let cycle = phase(at: timeline.date)
                MoonFill(
                    fill: cycle.lit,
                    active: active,
                    size: size,
                    waxing: cycle.waxing
                )
            }
        }
    }

    /// Position in the cycle: 0 → 1 waxing, then 1 → 0 waning, with the sun
    /// crossing to the other limb at full.
    private func phase(at date: Date) -> (lit: Double, waxing: Bool) {
        let seconds = date.timeIntervalSinceReferenceDate
        let turn = (seconds / max(period, 1)).truncatingRemainder(dividingBy: 1)
        return turn < 0.5
            ? (lit: turn * 2, waxing: true)
            : (lit: (1 - turn) * 2, waxing: false)
    }
}

/// The waist of the terminator ellipse as a fraction of the moon's radius.
/// 1 at new and full (the terminator is the rim itself), 0 at the quarters
/// (it is a straight line down the middle).
private func moonWaist(_ t: Double) -> Double { abs(2 * t - 1) }

/// Cubic approximation of a quarter ellipse. Four of these draw a circle to
/// within half a percent, which is far inside a 34pt icon.
private let kappa = 0.5522847498307936

/// Half an ellipse from `start` to `end` (both on the vertical axis through
/// `axisX`), bulging out to `peakX` at the midpoint.
private func halfEllipse(
    from start: CGPoint, to end: CGPoint, axisX: CGFloat, peakX: CGFloat, in path: inout Path
) {
    let midY = (start.y + end.y) / 2
    let radiusY = abs(end.y - start.y) / 2
    let dx = peakX - axisX
    let lean = CGFloat(kappa) * dx
    let rise = CGFloat(kappa) * radiusY
    let towardPeak: CGFloat = start.y < end.y ? 1 : -1

    path.addCurve(
        to: CGPoint(x: peakX, y: midY),
        control1: CGPoint(x: axisX + lean, y: start.y),
        control2: CGPoint(x: peakX, y: midY - towardPeak * rise)
    )
    path.addCurve(
        to: end,
        control1: CGPoint(x: peakX, y: midY + towardPeak * rise),
        control2: CGPoint(x: axisX + lean, y: end.y)
    )
}

/// The near side, as it actually looks.
///
/// A correct phase is not enough. Twice now this drew a geometrically perfect
/// crescent that still read as a white shape, because nothing about a smooth
/// two-tone wedge says "moon". Three things do, and all three are here:
///
/// 1. **The maria** — the dark basalt seas anyone recognises without being
///    able to name them. Each is several overlapping lobes, because a sea with
///    a circular outline reads as a sticker.
/// 2. **A crater field with relief** — every crater gets a shadow on the side
///    away from the sun and a bright rim toward it. That opposition is what
///    makes a surface look lit rather than painted.
/// 3. **Limb darkening** — a sphere dims toward its edge. Without it the disc
///    stays flat no matter how much detail is on it.
///
/// Positions are in units of the moon's radius from centre, x right and y
/// down, as seen from Earth with north up.
private struct Blob {
    let x: Double
    let y: Double
    let r: Double
    let depth: Double
}

/// Nine seas, each built from overlapping lobes so none has a circular edge.
private let maria: [Blob] = [
    // Oceanus Procellarum — the big western plain.
    Blob(x: -0.58, y: -0.18, r: 0.30, depth: 0.30),
    Blob(x: -0.50, y:  0.06, r: 0.27, depth: 0.28),
    Blob(x: -0.62, y: -0.42, r: 0.20, depth: 0.24),
    // Mare Imbrium.
    Blob(x: -0.28, y: -0.44, r: 0.25, depth: 0.38),
    Blob(x: -0.12, y: -0.38, r: 0.18, depth: 0.34),
    // Mare Serenitatis.
    Blob(x:  0.12, y: -0.36, r: 0.19, depth: 0.40),
    // Mare Tranquillitatis.
    Blob(x:  0.32, y: -0.10, r: 0.21, depth: 0.42),
    Blob(x:  0.20, y: -0.20, r: 0.14, depth: 0.36),
    // Mare Fecunditatis and Nectaris.
    Blob(x:  0.52, y:  0.14, r: 0.15, depth: 0.36),
    Blob(x:  0.31, y:  0.27, r: 0.12, depth: 0.34),
    // Mare Nubium and Humorum.
    Blob(x: -0.20, y:  0.32, r: 0.18, depth: 0.30),
    Blob(x: -0.47, y:  0.35, r: 0.13, depth: 0.28),
    // Mare Crisium — the detached oval near the eastern limb.
    Blob(x:  0.62, y: -0.26, r: 0.13, depth: 0.40),
    // Mare Frigoris, western end.
    Blob(x:  0.00, y: -0.66, r: 0.10, depth: 0.24),
]

/// Craters, placed once from a fixed seed so the moon is the same moon every
/// launch. Kept off the limb, where they would be edge-on anyway.
private let craterField: [Blob] = {
    var seed: UInt64 = 0x5EED_1234_ABCD
    func rnd() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((seed >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF)
    }
    var out: [Blob] = []
    while out.count < 46 {
        let x = rnd() * 2 - 1
        let y = rnd() * 2 - 1
        guard x * x + y * y < 0.80 else { continue }
        out.append(
            Blob(x: x, y: y, r: 0.016 + rnd() * 0.052, depth: 0.30 + rnd() * 0.38)
        )
    }
    // Tycho, the one crater with a name most people half-remember, and its ray
    // system. Placed by hand because the seed will not put it where it belongs.
    out.append(Blob(x: -0.11, y: 0.57, r: 0.055, depth: 0.5))
    return out
}()

private func drawMoon(
    in context: inout GraphicsContext,
    canvasSize: CGSize,
    fill: Double,
    waxing: Bool,
    active: Bool
) {
    let t = min(1, max(0, fill))
    let s = min(canvasSize.width, canvasSize.height)
    let scale = s / 200
    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    let moonR = 58 * scale

    // Which side the sun is on. Waxing is lit from the west (screen right),
    // waning from the east. The *surface* never mirrors -- the near side
    // always faces us -- only the lighting does.
    let sun: CGFloat = waxing ? 1 : -1

    let glowR = 78 * scale
    context.fill(
        Path(ellipseIn: CGRect(
            x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2
        )),
        with: .color(Theme.Family.sleep.opacity(active ? 0.28 : 0.12))
    )

    let discRect = CGRect(
        x: center.x - moonR, y: center.y - moonR, width: moonR * 2, height: moonR * 2
    )
    let disc = Path(ellipseIn: discRect)

    // The terminator of a real moon is its own rim seen at an angle, so it
    // projects to an ellipse exactly as tall as the disc whose waist closes to
    // nothing at the quarter and reopens to the full radius at new and full.
    // It bulges *into* the lit half while crescent and *away* once gibbous,
    // which is the whole reason a moon reads as a moon.
    //
    // This began as a second circle unioned into the disc and filled even-odd.
    // A circle is the wrong curve -- its waist cannot close, so there was no
    // quarter moon -- and wherever it reached past the rim the overhang lay
    // inside exactly one subpath, so even-odd filled it: a lens of moonlight
    // hanging off the side of the disc.
    let top = CGPoint(x: center.x, y: center.y - moonR)
    let bottom = CGPoint(x: center.x, y: center.y + moonR)
    let waist = moonR * CGFloat(moonWaist(t))
    let bulgesIntoLitHalf = t < 0.5

    var lit = Path()
    lit.move(to: top)
    halfEllipse(from: top, to: bottom, axisX: center.x, peakX: center.x + sun * moonR, in: &lit)
    halfEllipse(
        from: bottom,
        to: top,
        axisX: center.x,
        peakX: center.x + sun * (bulgesIntoLitHalf ? waist : -waist),
        in: &lit
    )
    lit.closeSubpath()

    // One textured sphere with a terminator across it, which is what a moon
    // actually looks like -- not a lit shape sitting beside a blank disc.
    //
    // An earlier version painted surface only inside the lit face, which at a
    // crescent threw nearly all of it away: Procellarum, Imbrium and Nubium
    // are all on the western half, so a 34%-lit moon clipped every one and
    // kept a bare sliver next to a flat circle. The whole disc is painted
    // first now and the night side dimmed afterwards, so the surface stays
    // faintly visible through it -- earthshine, and the reason a real crescent
    // still shows you the rest of the moon.
    context.drawLayer { face in
        face.clip(to: disc)
        face.fill(disc, with: .color(Theme.Family.Moon.lit))

        // Detail is worse than nothing when it lands on a couple of pixels,
        // and the film strip can draw thirty moons on one screen. Seas from
        // 54pt, the crater field only on the large moons that can show it.
        if s >= 54 {
            for mare in maria {
                softBlob(mare, in: &face, center: center, moonR: moonR,
                         tint: Theme.Family.Moon.dark, strength: mare.depth)
            }
        }

        if s >= 120 {
            for crater in craterField {
                let rr = CGFloat(crater.r) * moonR
                let spot = CGPoint(
                    x: center.x + CGFloat(crater.x) * moonR,
                    y: center.y + CGFloat(crater.y) * moonR
                )
                // Relief, not a dot. The floor shades away from the sun and the
                // far rim catches it; that opposition is the whole trick, and
                // it is why the surface looks lit instead of painted on.
                let offset = rr * 0.22
                softDisc(
                    at: CGPoint(x: spot.x - sun * offset, y: spot.y + offset * 0.35),
                    r: rr, tint: Theme.Family.Moon.dark,
                    strength: crater.depth * 0.72, in: &face
                )
                softDisc(
                    at: CGPoint(x: spot.x + sun * offset * 0.9, y: spot.y - offset * 0.5),
                    r: rr * 0.82, tint: .white,
                    strength: crater.depth * 0.42, in: &face
                )
            }
        }

        // Limb darkening: a sphere lit from the side falls off toward its edge.
        face.fill(
            disc,
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.12),
                    Color.clear,
                    Theme.Family.Moon.dark.opacity(0.42)
                ]),
                center: CGPoint(x: center.x + sun * moonR * 0.22, y: center.y - moonR * 0.24),
                startRadius: 0,
                endRadius: moonR * 1.32
            )
        )

        // Night side. `disc` plus `lit` under even-odd is exactly the unlit
        // crescent, because `lit` is wholly inside `disc` by construction --
        // no overhang, so nothing can be filled outside the rim this time.
        var night = Path()
        night.addPath(disc)
        night.addPath(lit)
        face.fill(
            night,
            with: .color(Theme.Family.Moon.dark.opacity(active ? 0.80 : 0.86)),
            style: FillStyle(eoFill: true)
        )
    }
}

/// A sea: soft-edged, and never a circle.
private func softBlob(
    _ blob: Blob,
    in context: inout GraphicsContext,
    center: CGPoint,
    moonR: CGFloat,
    tint: Color,
    strength: Double
) {
    softDisc(
        at: CGPoint(
            x: center.x + CGFloat(blob.x) * moonR,
            y: center.y + CGFloat(blob.y) * moonR
        ),
        r: CGFloat(blob.r) * moonR,
        tint: tint,
        strength: strength,
        in: &context
    )
}

/// A radial fill that fades to nothing, rather than a blurred disc.
///
/// A sea has no edge and a hard one reads as a sticker -- but a blur filter
/// per feature would be sixty offscreen passes on a single moon, and the film
/// strip draws one per night. A gradient to clear gives the same soft edge in
/// one fill.
private func softDisc(
    at spot: CGPoint,
    r: CGFloat,
    tint: Color,
    strength: Double,
    in context: inout GraphicsContext
) {
    guard r > 0.4 else { return }
    context.fill(
        Path(ellipseIn: CGRect(x: spot.x - r, y: spot.y - r, width: r * 2, height: r * 2)),
        with: .radialGradient(
            Gradient(stops: [
                .init(color: tint.opacity(strength), location: 0),
                .init(color: tint.opacity(strength * 0.72), location: 0.55),
                .init(color: tint.opacity(0), location: 1)
            ]),
            center: spot,
            startRadius: 0,
            endRadius: r
        )
    )
}

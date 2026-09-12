import SwiftUI

/// The moon, photographed rather than drawn.
///
/// In `Shared/` so the app and the widget extension draw the *same* moon.
/// `moonphase.waxing.crescent` was used in ten places across those targets and
/// is not a moon: its unlit half is a filled slab, so under `.hierarchical`
/// rendering it reads as a grey-and-white split sphere.
///
/// What replaced it first was vector art -- maria as soft blobs, a seeded
/// crater field, limb darkening -- and it went through four rounds of
/// refinement while still being told, correctly, that it looked like black and
/// white circles. It always would have. A drawn moon reads as a drawing at any
/// level of detail, and what a person recognises as the Moon is a photograph
/// of it: Tranquillitatis and Imbrium exactly where they belong, Tycho's rays
/// reaching halfway across the southern highlands, thousands of craters nobody
/// could name but everybody has seen.

// MARK: - Phase geometry

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

// MARK: - Drawing

/// A real full-moon photograph, cropped so the disc fills the frame edge to
/// edge, with an antialiased circular alpha.
///
/// Deliberately *fully lit*, carrying no shadow of its own: the phase is
/// applied below, in code, by dimming the part of the disc the sun has not
/// reached. That separation is what lets one image serve every phase, waxing
/// and waning, at any illumination -- and it is why this asset must never be
/// replaced with a crescent.
private let moonTexture = Image("MoonTexture")

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
    // The disc used to take 58% of its frame's width, which left it looking
    // like a small moon parked in a large empty box -- most visible in the
    // past-night strip, where the surrounding space read as part of the icon.
    // At 80 the disc is 80% of the frame, with the remainder left to the
    // halo rather than to nothing.
    let moonR = 80 * scale

    // Which limb the sun is on. Waxing is lit from the west (screen right),
    // waning from the east. The surface never mirrors -- the near side always
    // faces us -- only the lighting moves.
    let sun: CGFloat = waxing ? 1 : -1

    // Moonlight, not a purple disc.
    //
    // This was a flat fill of the app's sleep purple, which put a lilac ring
    // around every moon -- the more photographic the moon got, the more that
    // ring looked like a sticker behind it. A real moon casts its own light,
    // so the halo is the moon's own tone fading to nothing, and a gradient
    // rather than a flat disc so it has no edge to read as a ring.
    // 98 rather than 78: the halo now reaches the frame's edge, where the
    // gradient has already fallen to zero, so nothing clips.
    let glowR = 98 * scale
    context.fill(
        Path(ellipseIn: CGRect(
            x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2
        )),
        with: .radialGradient(
            Gradient(stops: [
                // Stops sit just inside the disc's edge (80/98 = 0.82 of the
                // glow radius) so the bright band of the halo hugs the limb
                // and fades outward. With the old 0.60/0.82 placement and the
                // larger disc, the whole bright part fell *under* the moon
                // and only the faint tail showed.
                .init(color: Theme.Family.Moon.lit.opacity(active ? 0.22 : 0.10), location: 0.78),
                .init(color: Theme.Family.Moon.lit.opacity(active ? 0.10 : 0.05), location: 0.90),
                .init(color: Theme.Family.Moon.lit.opacity(0), location: 1)
            ]),
            center: center,
            startRadius: 0,
            endRadius: glowR
        )
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

    context.drawLayer { face in
        face.clip(to: disc)

        // The whole disc, photographed. The night side is dimmed afterwards
        // rather than never drawn, so the surface stays faintly visible
        // through it -- earthshine, and the reason a real crescent still shows
        // you the rest of the moon.
        face.draw(moonTexture, in: discRect)

        // A warm cast, so the moon belongs to Zoon's palette rather than
        // sitting in it as a grey cut-out. Light enough to leave the
        // photograph's own tonality intact.
        face.fill(disc, with: .color(Theme.Family.Moon.lit.opacity(0.14)))

        // Limb darkening. The photograph is flat-lit by design, so the falloff
        // that makes a sphere look spherical has to be added here, and it has
        // to follow the sun rather than sit in the middle.
        face.fill(
            disc,
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.06),
                    Color.clear,
                    Theme.Family.Moon.dark.opacity(0.34)
                ]),
                center: CGPoint(x: center.x + sun * moonR * 0.24, y: center.y - moonR * 0.22),
                startRadius: 0,
                endRadius: moonR * 1.30
            )
        )

        // Night side. `disc` plus `lit` under even-odd is exactly the unlit
        // crescent, because `lit` is wholly inside `disc` by construction --
        // no overhang, so nothing can be filled outside the rim.
        var night = Path()
        night.addPath(disc)
        night.addPath(lit)
        let nightTone = Theme.Family.Moon.dark.opacity(active ? 0.84 : 0.88)

        if s >= 90 {
            // A real terminator is a band, not an edge: the sun sets over a
            // stretch of surface. One blur pass, and only where the hard edge
            // would be the thing you notice. The clip to `disc` is on the
            // enclosing layer, so softening the terminator cannot soften the
            // rim.
            face.drawLayer { dusk in
                dusk.addFilter(.blur(radius: moonR * 0.05))
                dusk.fill(night, with: .color(nightTone), style: FillStyle(eoFill: true))
            }
        } else {
            face.fill(night, with: .color(nightTone), style: FillStyle(eoFill: true))
        }
    }
}

// MARK: - Views

/// The moon at one phase. `fill` is the lit fraction: 0 new, 1 full.
struct MoonFill: View {
    var fill: Double
    var active: Bool
    var size: CGFloat = 28
    /// Lit from the west, as the moon is on its way to full. Waning lights the
    /// other limb -- the surface never mirrors, only the sun moves.
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
/// A full synodic cycle -- new, waxing crescent, first quarter, gibbous, full,
/// then back down the other limb -- compressed into `period` seconds. The
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
            // 20fps, not 60. The cycle takes 48 seconds, so a frame every 50ms
            // is already finer than the eye can resolve here, and three times
            // the work for motion nobody can see is battery spent for nothing.
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

    /// Position in the cycle: 0 to 1 waxing, then 1 back to 0 waning, with the
    /// sun crossing to the other limb at full.
    private func phase(at date: Date) -> (lit: Double, waxing: Bool) {
        let seconds = date.timeIntervalSinceReferenceDate
        let turn = (seconds / max(period, 1)).truncatingRemainder(dividingBy: 1)
        return turn < 0.5
            ? (lit: turn * 2, waxing: true)
            : (lit: (1 - turn) * 2, waxing: false)
    }
}

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

    var body: some View {
        Canvas { context, canvasSize in
            drawMoon(in: &context, canvasSize: canvasSize, fill: fill, active: active)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
/// A geometrically correct crescent is still just a white shape: the phase was
/// right and it read as a blob, because nothing about a flat two-tone wedge
/// says "moon". What says moon is the maria — the dark basalt seas anyone
/// would recognise without being able to name them — plus the way a sphere
/// dims toward its limb.
///
/// Positions are the real ones, in units of the moon's radius from the centre,
/// x right and y down, as seen from Earth with north up.
private struct Mare {
    let x: Double
    let y: Double
    let r: Double
    let depth: Double
}

private let maria: [Mare] = [
    Mare(x: -0.52, y: -0.10, r: 0.40, depth: 0.30),   // Oceanus Procellarum
    Mare(x: -0.26, y: -0.42, r: 0.29, depth: 0.38),   // Mare Imbrium
    Mare(x:  0.10, y: -0.36, r: 0.20, depth: 0.40),   // Mare Serenitatis
    Mare(x:  0.30, y: -0.10, r: 0.23, depth: 0.42),   // Mare Tranquillitatis
    Mare(x:  0.50, y:  0.14, r: 0.15, depth: 0.36),   // Mare Fecunditatis
    Mare(x:  0.30, y:  0.26, r: 0.12, depth: 0.34),   // Mare Nectaris
    Mare(x: -0.20, y:  0.30, r: 0.19, depth: 0.30),   // Mare Nubium
    Mare(x: -0.47, y:  0.34, r: 0.13, depth: 0.28),   // Mare Humorum
    Mare(x:  0.04, y: -0.62, r: 0.11, depth: 0.26),   // Mare Frigoris, western end
]

/// A few bright-rimmed craters. Small, and the reason the lower third does not
/// read as empty.
private let craters: [Mare] = [
    Mare(x: -0.10, y:  0.56, r: 0.07, depth: -0.34),  // Tycho
    Mare(x: -0.34, y:  0.62, r: 0.05, depth: -0.22),
    Mare(x:  0.42, y: -0.44, r: 0.05, depth: -0.20),
    Mare(x:  0.16, y:  0.46, r: 0.04, depth: -0.18),
]

private func drawMoon(
    in context: inout GraphicsContext,
    canvasSize: CGSize,
    fill: Double,
    active: Bool
) {
    let t = min(1, max(0, fill))
    let s = min(canvasSize.width, canvasSize.height)
    let scale = s / 200
    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    let moonR = 58 * scale

    let glowR = 78 * scale
    let glow = Path(ellipseIn: CGRect(
        x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2
    ))
    context.fill(glow, with: .color(Theme.Family.sleep.opacity(active ? 0.28 : 0.12)))

    let discRect = CGRect(
        x: center.x - moonR, y: center.y - moonR, width: moonR * 2, height: moonR * 2
    )
    let disc = Path(ellipseIn: discRect)

    // One textured sphere with a terminator across it, which is what a moon
    // actually looks like -- not a lit shape sitting next to a blank disc.
    //
    // The first version painted surface only inside the lit face. At a
    // crescent that threw almost all of it away: Procellarum, Imbrium and
    // Nubium are all on the western half, so a 34%-lit moon clipped every one
    // of them and kept a bare sliver. What was left was a plain wedge beside a
    // flat purple circle, which is precisely the "white dot" this is meant to
    // stop being.
    //
    // So the whole disc is painted first, seas and all, and the unlit part is
    // *dimmed* afterwards rather than never drawn. The surface stays faintly
    // visible through it, which is earthshine, and is why a real crescent
    // still shows you the rest of the moon.
    let top = CGPoint(x: center.x, y: center.y - moonR)
    let bottom = CGPoint(x: center.x, y: center.y + moonR)
    let waist = moonR * CGFloat(moonWaist(t))
    let bulgesIntoLitHalf = t < 0.5

    // The terminator of a real moon is its own rim seen at an angle, so it
    // projects to an ellipse exactly as tall as the disc whose waist closes to
    // nothing at the quarter and reopens to the full radius at new and full.
    // It bulges *into* the lit half while waxing to a crescent and *away* from
    // it once gibbous, which is the whole reason a moon reads as a moon.
    //
    // This used to be a second circle unioned into the disc and filled
    // even-odd. A circle is the wrong curve -- its waist cannot close, so
    // there was no quarter moon -- and wherever it reached past the rim the
    // overhang lay inside exactly one subpath, so even-odd filled it: a lens
    // of moonlight hanging off the side of the disc.
    var lit = Path()
    lit.move(to: top)
    halfEllipse(from: top, to: bottom, axisX: center.x, peakX: center.x + moonR, in: &lit)
    halfEllipse(
        from: bottom,
        to: top,
        axisX: center.x,
        peakX: center.x + (bulgesIntoLitHalf ? waist : -waist),
        in: &lit
    )
    lit.closeSubpath()

    context.drawLayer { face in
        face.clip(to: disc)
        face.fill(disc, with: .color(Theme.Family.Moon.lit))

        // Detail costs nothing to skip and is worse than nothing when it lands
        // on a couple of pixels. Below roughly 54pt the maria would be grey
        // mush, so small moons stay a clean phase. That also keeps the film
        // strip cheap, which can be thirty moons on one screen.
        if s >= 54 {
            for mare in maria + craters {
                let rr = CGFloat(mare.r) * moonR
                let spot = CGPoint(
                    x: center.x + CGFloat(mare.x) * moonR,
                    y: center.y + CGFloat(mare.y) * moonR
                )
                let rect = CGRect(
                    x: spot.x - rr, y: spot.y - rr, width: rr * 2, height: rr * 2
                )
                // A soft radial fill rather than a blurred disc. A mare has no
                // edge, and a hard one reads as a sticker -- but a blur filter
                // per sea would be thirteen offscreen passes per moon, and the
                // film strip draws a moon per night.
                let base: Color = mare.depth < 0 ? Color.white : Theme.Family.Moon.dark
                let strength = abs(mare.depth)
                face.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: base.opacity(strength), location: 0),
                            .init(color: base.opacity(strength * 0.74), location: 0.55),
                            .init(color: base.opacity(0), location: 1)
                        ]),
                        center: spot,
                        startRadius: 0,
                        endRadius: rr
                    )
                )
            }
        }

        // Limb darkening: a sphere lit from the side falls off toward its edge.
        // Without it the disc stays flat however much surface is painted on.
        face.fill(
            disc,
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.12),
                    Color.clear,
                    Theme.Family.Moon.dark.opacity(0.40)
                ]),
                center: CGPoint(x: center.x + moonR * 0.22, y: center.y - moonR * 0.24),
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

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
    context.fill(Path(ellipseIn: discRect), with: .color(Theme.Family.Moon.body.opacity(0.32)))

    // The lit face as a single closed path: down the right rim, then back up
    // the terminator.
    //
    // The terminator of a real moon is its own rim seen at an angle, so it
    // projects to an ellipse exactly as tall as the disc whose waist closes to
    // nothing at the quarter and reopens to the full radius at new and full.
    // It bulges *into* the lit half while waxing to a crescent and *away* from
    // it once gibbous, which is the whole reason a moon reads as a moon.
    //
    // This used to be a second circle unioned into the disc and filled
    // even-odd. Two things went wrong with that. A circle is the wrong curve --
    // its waist cannot close, so there was no quarter moon. Worse, wherever
    // that circle reached past the rim the overhang lay inside exactly one
    // subpath, so even-odd filled it: a lens of moonlight hanging off the side
    // of the disc, which is the white blob that showed up down the week strip.
    let top = CGPoint(x: center.x, y: center.y - moonR)
    let bottom = CGPoint(x: center.x, y: center.y + moonR)
    let waist = moonR * CGFloat(moonWaist(t))
    let bulgesIntoLitHalf = t < 0.5

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

    context.fill(lit, with: .color(Theme.Family.Moon.lit))
}

import Foundation
import CoreGraphics

/// Where everything in the Recovery radar is drawn.
///
/// **The defect this replaces.** The radar used to place each signal's icon
/// at its own value radius, held out to a floor:
///
/// ```swift
/// private static let markerFloor: Double = 0.42
/// let plotted = max(markerFloor * grown, value(of: component))
/// ```
///
/// Two things were wrong with that, and only one of them was visible.
///
/// The visible one: at a radar radius of 95, the floor put a 22-point filled
/// disc centred 39.9 points from the middle, spanning 29 to 51 — straight
/// through "RECOVERY" above the score and through the "%" beside it. No
/// amount of padding around the centre text could fix it, because the marker
/// was being positioned relative to the centre, not to the text.
///
/// The one nobody could see: a signal at 10% and a signal at 42% put their
/// icons in exactly the same place. The floor existed to stop icons landing
/// on the numerals, and the cost of it was that marker position stopped
/// meaning anything below 42%. A reader comparing two axes by eye was
/// comparing two clamped values.
///
/// **What replaces it.** Identity and value are separated, which is the
/// standard way radar charts with labels are built:
///
/// - the **icon** sits at a fixed point on its axis, at `iconRadius`, the
///   same place whatever the value is. It is an axis label, and an axis
///   label that moves is not one.
/// - the **polygon vertex** sits at the true normalized value, scaled to
///   `dataRadius`, with nothing clamped.
///
/// Because the icons no longer have to dodge the numerals, the polygon does
/// not either, and the value can be plotted honestly all the way to zero.
///
/// ```text
///                  HRV
///                   ●            ← icon, fixed at iconRadius
///                   |
///               ╱───┼───╲        ← polygon, vertices at true value
///      RHR ●────┤   ·   ├────● Sleep
///               ╲───┼───╱        ← · is the centre exclusion
///                   |
///                   ●
///                  Resp
/// ```
enum RecoveryRadarGeometry {

    /// How far out the identity icons sit, as a fraction of the radar radius.
    ///
    /// Leaves exactly `iconDiameter / 2` inside the edge, so an icon's outer
    /// edge meets the radar's own bounds and nothing spills into the ring
    /// stroke drawn around it.
    static let iconDiameter: CGFloat = 22

    /// How far out a full-value vertex reaches, as a fraction of the radius.
    ///
    /// Short of the icons on purpose. A polygon that reached them would have
    /// its vertices tangled in the labels at exactly the values a reader most
    /// wants to see clearly — the high ones.
    static let dataFraction: CGFloat = 0.74

    /// Inside this, the score owns the space.
    ///
    /// Nothing that carries identity — no icon, no label, no value dot — is
    /// drawn here, and the grid and the polygon wash fade out through it so
    /// the numerals sit on a clean ground. The polygon itself is not clipped:
    /// a low signal still draws its vertex inward, because that collapse *is*
    /// the reading, and hiding it would be the floor's mistake in another
    /// form.
    ///
    /// **0.55 is measured, not chosen.** In the shipping hero the centre
    /// stack is "RECOVERY" over the score over the band name; at a ring of
    /// 236 the score is set in `numeral(236 × 0.26)` ≈ 61pt, which makes the
    /// stack about 100 points tall and 88 wide. Half of that is 50 points
    /// vertically against a radar radius of 95 — so the score's own footprint
    /// is 0.53 of the radius, and the zone has to be at least that or it is
    /// describing a smaller area than the text actually occupies.
    ///
    /// A first pass at this used 0.30, which is 28.5 points: comfortably
    /// *inside* the numerals it was supposed to be protecting, and small
    /// enough that the old 0.42 marker floor would have cleared it. A guard
    /// that the defect passes is not a guard.
    static let centreExclusionFraction: CGFloat = 0.55

    /// Straight up for the first signal, then clockwise, in radians.
    ///
    /// Radians rather than SwiftUI's `Angle` so this layer stays plain
    /// geometry that a test can exercise without a view.
    static func axisAngle(index: Int, count: Int) -> Double {
        -.pi / 2 + 2 * .pi * Double(index) / Double(max(count, 1))
    }

    static func iconRadius(radarRadius: CGFloat) -> CGFloat {
        max(0, radarRadius - iconDiameter / 2)
    }

    static func dataRadius(radarRadius: CGFloat) -> CGFloat {
        radarRadius * dataFraction
    }

    static func centreExclusionRadius(radarRadius: CGFloat) -> CGFloat {
        radarRadius * centreExclusionFraction
    }

    /// A point on an axis, `distance` from the centre of a `radarRadius` box.
    static func point(
        index: Int,
        count: Int,
        radarRadius: CGFloat,
        distance: CGFloat
    ) -> CGPoint {
        let angle = axisAngle(index: index, count: count)
        return CGPoint(
            x: radarRadius + CGFloat(cos(angle)) * distance,
            y: radarRadius + CGFloat(sin(angle)) * distance
        )
    }

    /// Where a signal's identity icon goes. Independent of its value — that
    /// is the whole point.
    static func iconPoint(index: Int, count: Int, radarRadius: CGFloat) -> CGPoint {
        point(
            index: index, count: count, radarRadius: radarRadius,
            distance: iconRadius(radarRadius: radarRadius)
        )
    }

    /// Where a signal's polygon vertex goes: its true normalized value,
    /// nothing clamped.
    ///
    /// - Parameter normalized: 0...1, or 0 for a signal that was not
    ///   measured. An unmeasured axis collapses to the centre rather than
    ///   resting at a guess — a watch left on the nightstand must not draw
    ///   the same shape as a body under strain.
    static func valuePoint(
        index: Int,
        count: Int,
        radarRadius: CGFloat,
        normalized: Double
    ) -> CGPoint {
        let clamped = min(1, max(0, normalized))
        return point(
            index: index, count: count, radarRadius: radarRadius,
            distance: dataRadius(radarRadius: radarRadius) * CGFloat(clamped)
        )
    }

    /// Whether a value dot may be drawn at this vertex.
    ///
    /// False inside the exclusion zone. The dot is a precision affordance,
    /// and a precision affordance printed over the score is worth less than
    /// the score is — the polygon still carries the value there.
    static func drawsValueDot(normalized: Double) -> Bool {
        min(1, max(0, normalized)) * Double(dataFraction) >= Double(centreExclusionFraction)
    }

    /// Distance from the centre, for a point in a `radarRadius` box.
    static func distanceFromCentre(_ point: CGPoint, radarRadius: CGFloat) -> CGFloat {
        let dx = point.x - radarRadius
        let dy = point.y - radarRadius
        return sqrt(dx * dx + dy * dy)
    }
}

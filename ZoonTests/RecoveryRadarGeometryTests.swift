import XCTest
import CoreGraphics

/// The Recovery hero overlap, as geometry that can be proved rather than a
/// screenshot that has to be looked at.
///
/// The defect was a marker floor: every signal's icon was drawn at
/// `max(0.42, value)` of the radar radius, so at radius 95 a 22-point filled
/// disc sat 39.9 points from the middle — across "RECOVERY" and the "%".
/// The floor existed to keep icons off the numerals and put them there
/// instead, while also making every value below 42% plot in the same place.
final class RecoveryRadarGeometryTests: XCTestCase {

    /// The shipping hero: a 190-point radar inside a 236-point ring.
    private let radius: CGFloat = 95
    private let count = 4

    /// The values the brief asks for, as normalized fractions.
    private let recoveries: [Double] = [0, 0.09, 0.41, 0.67, 0.88, 1.0]

    private func exclusion() -> CGFloat {
        RecoveryRadarGeometry.centreExclusionRadius(radarRadius: radius)
    }

    private func distance(_ point: CGPoint) -> CGFloat {
        RecoveryRadarGeometry.distanceFromCentre(point, radarRadius: radius)
    }

    // MARK: - The central exclusion zone

    /// The assertion the old code could not have passed. Its own floor put
    /// icons at 0.42 × 95 = 39.9, inside any honest exclusion zone.
    func testNoIconEntersTheCentralExclusionZoneAtAnyValue() {
        for index in 0..<count {
            let point = RecoveryRadarGeometry.iconPoint(
                index: index, count: count, radarRadius: radius
            )
            XCTAssertGreaterThan(
                distance(point), exclusion(),
                "the \(index)th axis icon sits inside the score's space"
            )
        }
    }

    /// An icon's *outer edge*, not just its centre, has to clear the zone —
    /// a 22-point disc is 11 points of overlap waiting to happen.
    func testNoIconEdgeReachesTheCentralExclusionZone() {
        let inner = RecoveryRadarGeometry.iconRadius(radarRadius: radius)
            - RecoveryRadarGeometry.iconDiameter / 2
        XCTAssertGreaterThan(inner, exclusion())
    }

    /// And the icon must stay inside the radar, or it lands on the ring
    /// stroke drawn around it.
    func testNoIconEdgeLeavesTheRadar() {
        let outer = RecoveryRadarGeometry.iconRadius(radarRadius: radius)
            + RecoveryRadarGeometry.iconDiameter / 2
        XCTAssertLessThanOrEqual(outer, radius)
    }

    /// The old floor, stated as the regression it was, so the number cannot
    /// come back.
    func testTheOldMarkerFloorWouldHaveLandedInsideTheExclusionZone() {
        let oldFloorDistance = radius * 0.42
        XCTAssertLessThan(
            oldFloorDistance, exclusion(),
            "0.42 of the radius is no longer inside the score's space, so this test has stopped testing anything"
        )
    }

    // MARK: - Identity does not move

    /// The heart of the redesign: an icon is an axis label, and an axis label
    /// that moves with its value is not one.
    func testAnIconIsInTheSamePlaceWhateverTheValue() {
        let point = RecoveryRadarGeometry.iconPoint(index: 0, count: count, radarRadius: radius)
        for _ in recoveries {
            XCTAssertEqual(
                RecoveryRadarGeometry.iconPoint(index: 0, count: count, radarRadius: radius),
                point
            )
        }
    }

    func testTheFirstAxisPointsStraightUpAndTheRestGoClockwise() {
        let up = RecoveryRadarGeometry.iconPoint(index: 0, count: 4, radarRadius: radius)
        let right = RecoveryRadarGeometry.iconPoint(index: 1, count: 4, radarRadius: radius)
        let down = RecoveryRadarGeometry.iconPoint(index: 2, count: 4, radarRadius: radius)
        let left = RecoveryRadarGeometry.iconPoint(index: 3, count: 4, radarRadius: radius)

        XCTAssertEqual(up.x, radius, accuracy: 0.001)
        XCTAssertLessThan(up.y, radius)
        XCTAssertGreaterThan(right.x, radius)
        XCTAssertEqual(right.y, radius, accuracy: 0.001)
        XCTAssertGreaterThan(down.y, radius)
        XCTAssertLessThan(left.x, radius)
    }

    // MARK: - Value stays true

    /// Nothing is clamped any more. The old floor made 9% and 41% draw in
    /// exactly the same place; they must not now.
    func testTwoDifferentValuesPlotInTwoDifferentPlaces() {
        let low = RecoveryRadarGeometry.valuePoint(
            index: 0, count: count, radarRadius: radius, normalized: 0.09
        )
        let mid = RecoveryRadarGeometry.valuePoint(
            index: 0, count: count, radarRadius: radius, normalized: 0.41
        )
        XCTAssertNotEqual(distance(low), distance(mid), accuracy: 0.5)
        XCTAssertLessThan(distance(low), distance(mid))
    }

    /// The vertex is exactly the value, scaled — no floor, no easing.
    func testAVertexSitsAtItsTrueFractionOfTheDataRadius() {
        let dataRadius = RecoveryRadarGeometry.dataRadius(radarRadius: radius)
        for value in recoveries {
            let point = RecoveryRadarGeometry.valuePoint(
                index: 0, count: count, radarRadius: radius, normalized: value
            )
            XCTAssertEqual(
                distance(point), dataRadius * CGFloat(value), accuracy: 0.001,
                "value \(value) did not plot at its own radius"
            )
        }
    }

    /// Zero is the centre. An unmeasured signal collapses there rather than
    /// resting at a floor that would read as a real low reading.
    func testAnUnmeasuredSignalCollapsesToTheCentre() {
        let point = RecoveryRadarGeometry.valuePoint(
            index: 0, count: count, radarRadius: radius, normalized: 0
        )
        XCTAssertEqual(distance(point), 0, accuracy: 0.001)
    }

    func testValuesOutsideTheRangeAreClampedRatherThanDrawnOutsideTheRadar() {
        let over = RecoveryRadarGeometry.valuePoint(
            index: 0, count: count, radarRadius: radius, normalized: 4
        )
        let under = RecoveryRadarGeometry.valuePoint(
            index: 0, count: count, radarRadius: radius, normalized: -2
        )
        XCTAssertEqual(distance(over), RecoveryRadarGeometry.dataRadius(radarRadius: radius), accuracy: 0.001)
        XCTAssertEqual(distance(under), 0, accuracy: 0.001)
    }

    /// A full-value vertex must not reach the icons, or the polygon's most
    /// interesting points are drawn through its labels.
    func testAFullValueVertexStopsShortOfTheIcons() {
        let full = RecoveryRadarGeometry.dataRadius(radarRadius: radius)
        let iconInner = RecoveryRadarGeometry.iconRadius(radarRadius: radius)
            - RecoveryRadarGeometry.iconDiameter / 2
        XCTAssertLessThan(full, iconInner)
    }

    // MARK: - Value dots

    /// The dot carries no identity, so it may sit anywhere the polygon can —
    /// except over the score.
    func testAValueDotIsSuppressedOnlyWhereItWouldLandOnTheScore() {
        XCTAssertFalse(RecoveryRadarGeometry.drawsValueDot(normalized: 0.05))
        XCTAssertTrue(RecoveryRadarGeometry.drawsValueDot(normalized: 0.9))

        for value in recoveries where RecoveryRadarGeometry.drawsValueDot(normalized: value) {
            let point = RecoveryRadarGeometry.valuePoint(
                index: 0, count: count, radarRadius: radius, normalized: value
            )
            XCTAssertGreaterThanOrEqual(
                distance(point), exclusion() - 0.001,
                "a dot was allowed at \(value), inside the score's space"
            )
        }
    }

    // MARK: - Other geometries

    /// The hero is one size today, but the component takes any, and the
    /// invariants are about ratios rather than about 95.
    func testTheExclusionZoneHoldsAtEveryRadarSize() {
        for radarRadius in [CGFloat(60), 80, 95, 120, 160] {
            let iconInner = RecoveryRadarGeometry.iconRadius(radarRadius: radarRadius)
                - RecoveryRadarGeometry.iconDiameter / 2
            XCTAssertGreaterThan(
                iconInner,
                RecoveryRadarGeometry.centreExclusionRadius(radarRadius: radarRadius),
                "icons collide with the score at radius \(radarRadius)"
            )
        }
    }

    /// Three signals, or five, still tile the circle evenly and still keep
    /// their icons out of the centre.
    func testOtherSignalCountsKeepTheirIconsOutOfTheCentre() {
        for signals in 1...6 {
            for index in 0..<signals {
                let point = RecoveryRadarGeometry.iconPoint(
                    index: index, count: signals, radarRadius: radius
                )
                XCTAssertEqual(
                    distance(point),
                    RecoveryRadarGeometry.iconRadius(radarRadius: radius),
                    accuracy: 0.001,
                    "\(signals) signals, axis \(index)"
                )
            }
        }
    }

    func testAnEmptyRadarDoesNotDivideByZero() {
        let point = RecoveryRadarGeometry.iconPoint(index: 0, count: 0, radarRadius: radius)
        XCTAssertFalse(point.x.isNaN)
        XCTAssertFalse(point.y.isNaN)
    }
}

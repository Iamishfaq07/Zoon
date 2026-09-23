import XCTest

/// The night's heart rate is the night's, and availability is what can be drawn.
final class OvernightSeriesTests: XCTestCase {

    private let bed = Date(timeIntervalSince1970: 1_700_000_000)
    private var wake: Date { bed.addingTimeInterval(8 * 3600) }
    private var night: DateInterval { DateInterval(start: bed, end: wake) }

    /// The defect: the day since waking, handed to an overnight chart.
    func testADaytimeOnlySeriesIsNotPlottable() {
        let daytime = (1...10).map { (date: wake.addingTimeInterval(Double($0) * 3600), bpm: 70.0) }
        XCTAssertEqual(daytime.count, 10)
        XCTAssertFalse(OvernightSeries.isPlottable(daytime, over: night))
        XCTAssertNil(OvernightSeries.nearest(to: wake, in: daytime, over: night, tolerance: 3600 * 2))
    }

    func testANightSeriesIsPlottable() {
        let overnight = (1...20).map { (date: bed.addingTimeInterval(Double($0) * 1200), bpm: 55.0) }
        XCTAssertTrue(OvernightSeries.isPlottable(overnight, over: night))
    }

    /// One point in the night is not a line.
    func testOnePointInsideIsNotALine() {
        let series = [(date: bed.addingTimeInterval(3600), bpm: 55.0), (date: wake.addingTimeInterval(60), bpm: 70.0)]
        XCTAssertFalse(OvernightSeries.isPlottable(series, over: night))
    }

    /// End points count; a gap in the middle is left as a gap.
    func testEndPointsAndGaps() {
        let series = [(date: bed, bpm: 60.0), (date: wake, bpm: 58.0)]
        XCTAssertEqual(OvernightSeries.clipped(series, to: night).count, 2)
        XCTAssertNil(OvernightSeries.nearest(to: bed.addingTimeInterval(4 * 3600), in: series, over: night))
    }

    func testNonFiniteReadingsAreDropped() {
        let series = [(date: bed.addingTimeInterval(60), bpm: Double.nan), (date: bed.addingTimeInterval(120), bpm: 0)]
        XCTAssertTrue(OvernightSeries.clipped(series, to: night).isEmpty)
    }

    func testTheDemoNightStaysInsideItsNight() {
        let demo = MockData.overnightHeartRate(bedtime: bed, wakeTime: wake)
        XCTAssertGreaterThan(demo.count, 50)
        XCTAssertEqual(OvernightSeries.clipped(demo, to: night).count, demo.count)
    }
}

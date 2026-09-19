import XCTest

/// When a metric stopped, as opposed to how much of it there is.
final class DataQualityLapseTests: XCTestCase {

    private func lapse(_ metric: DataQuality.Metric, in nights: [SleepNightFeatures]) -> DataQuality.Lapse {
        DataQuality.lapses(nights: nights).first { $0.metric == metric }!
    }

    /// The distinction the whole type exists for. Both of these histories have
    /// the same HRV coverage -- half the nights -- and they are completely
    /// different situations: one is a watch charged irregularly, the other is
    /// something that broke on a particular night and has not worked since.
    func testTheSameCoverageCanMeanArrivingOrStopped() {
        let scattered = (0..<10).map { index in
            Fixture.night(daysAgo: 10 - index, avgHRV: index.isMultiple(of: 2) ? 55 : nil)
        }
        let stoppedDead = (0..<10).map { index in
            Fixture.night(daysAgo: 10 - index, avgHRV: index < 5 ? 55 : nil)
        }

        let a = DataQuality.compute(nights: scattered).coverage.first { $0.metric == .hrv }!
        let b = DataQuality.compute(nights: stoppedDead).coverage.first { $0.metric == .hrv }!
        XCTAssertEqual(a.presentNightCount, b.presentNightCount, "the premise: same coverage")

        // The most recent scattered night is index 9, which is odd, so it has
        // no HRV either -- both histories end on a gap. What differs is how
        // long the gap has been running.
        XCTAssertEqual(lapse(.hrv, in: scattered).nightsSince, 1)
        XCTAssertEqual(lapse(.hrv, in: stoppedDead).nightsSince, 5)
    }

    func testAMetricInTheMostRecentNightIsCurrent() {
        let nights = (0..<5).map { Fixture.night(daysAgo: 5 - $0, avgHRV: 55) }
        XCTAssertEqual(lapse(.hrv, in: nights).status, .current)
        XCTAssertEqual(lapse(.hrv, in: nights).nightsSince, 0)
    }

    func testAStoppedMetricReportsHowLongAgo() {
        let nights = (0..<8).map { index in
            Fixture.night(daysAgo: 8 - index, avgHRV: index < 5 ? 55 : nil)
        }
        let l = lapse(.hrv, in: nights)
        XCTAssertEqual(l.status, .lapsed(nights: 3))
        XCTAssertNotNil(l.lastSeen)
        XCTAssertTrue(l.summary.contains("3"), l.summary)
    }

    /// Never seen is not the same claim as stopped, and saying the wrong one
    /// blames the wrong thing. A metric that never appeared is usually a
    /// device that does not measure it or a permission never granted -- not a
    /// sensor that failed.
    func testNeverSeenIsNotTheSameAsStopped() {
        let nights = (0..<6).map { Fixture.night(daysAgo: 6 - $0, avgSpO2: nil) }
        let l = lapse(.spo2, in: nights)
        XCTAssertEqual(l.status, .neverSeen)
        XCTAssertNil(l.lastSeen)
        XCTAssertEqual(l.nightsSince, 0, "a never-seen metric has no lapse length to report")
        XCTAssertFalse(l.summary.lowercased().contains("last"), l.summary)
        XCTAssertNotEqual(l.status, .lapsed(nights: 6))
    }

    func testAnEmptyHistorySaysSoRatherThanBlamingTheDevice() {
        let l = lapse(.hrv, in: [])
        XCTAssertEqual(l.status, .neverSeen)
        XCTAssertEqual(l.nightsConsidered, 0)
        XCTAssertTrue(l.summary.lowercased().contains("no nights"), l.summary)
    }

    /// Order is not trusted, the same as `compute` does not trust it.
    func testUnorderedHistoryGivesTheSameAnswer() {
        let nights = (0..<8).map { index in
            Fixture.night(daysAgo: 8 - index, avgHRV: index < 5 ? 55 : nil)
        }
        XCTAssertEqual(
            DataQuality.lapses(nights: nights.shuffled()).first { $0.metric == .hrv }!.nightsSince,
            lapse(.hrv, in: nights).nightsSince
        )
    }

    /// Sleep is special by construction: a night's presence in the array is
    /// its sleep measurement, so that row can only read current or, on an
    /// empty history, never seen. Asserted so nobody reads it as a bug.
    func testSleepCanOnlyBeCurrentOrNeverSeen() {
        let nights = (0..<3).map { Fixture.night(daysAgo: 3 - $0) }
        XCTAssertEqual(lapse(.sleep, in: nights).status, .current)
        XCTAssertEqual(lapse(.sleep, in: []).status, .neverSeen)
    }

    /// Every metric gets a row, so the diagnostic screen lines up with
    /// `coverage` rather than silently dropping the ones with nothing to say.
    func testEveryMetricGetsARow() {
        let nights = (0..<3).map { Fixture.night(daysAgo: 3 - $0) }
        XCTAssertEqual(DataQuality.lapses(nights: nights).count, DataQuality.Metric.allCases.count)
    }
}

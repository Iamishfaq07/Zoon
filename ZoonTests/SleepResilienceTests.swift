import XCTest

/// Resilience is "how many nights to get back inside your own band", measured
/// against the person's own history. Nothing here compares them to anyone else.
final class SleepResilienceTests: XCTestCase {

    /// Builds a run of nights from a disruption mask. `true` is a night
    /// outside the band, in the unfavourable direction.
    private func observations(_ disrupted: [Bool]) -> [SleepResilience.Observation] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return disrupted.enumerated().map { index, isDisrupted in
            SleepResilience.Observation(
                date: start.addingTimeInterval(Double(index) * 86_400),
                // Band is 50 ± 10, so 35 is outside it and 50 is inside.
                value: isDisrupted ? 35 : 50
            )
        }
    }

    private func measure(_ disrupted: [Bool]) -> SleepResilience.Result {
        SleepResilience.measure(
            observations: observations(disrupted),
            baseline: 50,
            tolerance: 10,
            direction: .belowIsDisruption
        )
    }

    private func calm(_ count: Int) -> [Bool] { Array(repeating: false, count: count) }
    private func dip(_ count: Int) -> [Bool] { Array(repeating: true, count: count) }

    // MARK: - Gates

    func testShortHistoryIsNotMeasured() {
        let result = measure(calm(10))
        XCTAssertEqual(
            result.state,
            .insufficientHistory(nights: 10, required: SleepResilience.minimumNights)
        )
        XCTAssertNil(result.state.medianNights)
    }

    /// A band of zero width makes every night a disruption. That is a broken
    /// baseline, not a fragile person, and must not be reported as one.
    func testZeroToleranceIsTreatedAsNoBaseline() {
        let result = SleepResilience.measure(
            observations: observations(calm(30)),
            baseline: 50,
            tolerance: 0,
            direction: .belowIsDisruption
        )
        XCTAssertNil(result.state.medianNights)
        XCTAssertEqual(result.eventCount, 0)
    }

    func testNeverLeavingTheBandIsSteadyNotMissing() {
        let result = measure(calm(30))
        XCTAssertEqual(result.state, .steady, "a signal that never wobbles has nothing to recover from")
        XCTAssertEqual(result.eventCount, 0)
    }

    func testOneOrTwoDisruptionsAreAnecdotesNotAPattern() {
        let result = measure(calm(10) + dip(1) + calm(10) + dip(1) + calm(8))
        XCTAssertEqual(
            result.state,
            .tooFewEvents(found: 2, required: SleepResilience.minimumEvents)
        )
        XCTAssertNil(result.state.medianNights)
    }

    // MARK: - Measurement

    func testThreeSingleNightDipsMeasureOneNight() {
        let result = measure(calm(5) + dip(1) + calm(5) + dip(1) + calm(5) + dip(1) + calm(10))
        XCTAssertEqual(result.state.medianNights, 1)
        XCTAssertEqual(result.eventCount, 3)
        XCTAssertEqual(result.censoredCount, 0)
    }

    func testMedianOfUnequalReturnTimes() {
        // Return times 1, 3, 5 -> median 3.
        let result = measure(calm(4) + dip(1) + calm(4) + dip(3) + calm(4) + dip(5) + calm(6))
        XCTAssertEqual(result.state.medianNights, 3)
        XCTAssertEqual(result.eventCount, 3)
    }

    /// A stretch of consecutive bad nights is one disruption that took a while
    /// to clear, not several separate ones.
    func testConsecutiveBadNightsAreOneEvent() {
        let result = measure(calm(10) + dip(4) + calm(5) + dip(1) + calm(5) + dip(1) + calm(5))
        XCTAssertEqual(result.eventCount, 3, "a four-night run is one event")
        XCTAssertEqual(result.state.medianNights, 1)
    }

    // MARK: - Censoring

    /// A disruption still ongoing when the window ends has no return time yet.
    /// It is counted and reported, and it cannot drag the median down.
    func testOngoingDisruptionIsCountedButNotGivenATime() {
        let result = measure(calm(6) + dip(1) + calm(6) + dip(1) + calm(6) + dip(3))
        XCTAssertEqual(result.eventCount, 3)
        XCTAssertEqual(result.censoredCount, 1, "the run touching the end has not resolved")
        XCTAssertEqual(
            result.state.medianNights, 1,
            "the censored event is longer than both observed ones, so it sorts last"
        )
    }

    /// Only the run touching the end of the window can be censored, which is
    /// what keeps the median identifiable at three or more events.
    func testAtMostOneEventIsEverCensored() {
        let result = measure(calm(4) + dip(2) + calm(4) + dip(2) + calm(4) + dip(2) + calm(4) + dip(2))
        XCTAssertLessThanOrEqual(result.censoredCount, 1)
        XCTAssertEqual(result.state.medianNights, 2)
    }

    // MARK: - Direction

    /// HRV falling is the disruption; resting heart rate rising is. A metric
    /// moving the favourable way is not something to recover from.
    func testFavourableDeviationIsNotADisruption() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let values: [Double] = (0..<30).map { $0.isMultiple(of: 7) ? 95 : 50 }
        let observations = values.enumerated().map {
            SleepResilience.Observation(
                date: start.addingTimeInterval(Double($0.offset) * 86_400), value: $0.element
            )
        }

        let asHRV = SleepResilience.measure(
            observations: observations, baseline: 50, tolerance: 10, direction: .belowIsDisruption
        )
        XCTAssertEqual(asHRV.state, .steady, "HRV well above baseline is not a disruption")

        let asRestingHR = SleepResilience.measure(
            observations: observations, baseline: 50, tolerance: 10, direction: .aboveIsDisruption
        )
        XCTAssertNotNil(asRestingHR.state.medianNights, "the same spikes read as disruptions for RHR")
    }
}

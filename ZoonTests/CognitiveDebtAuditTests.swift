import XCTest

/// The spec's 14-night weighted-window form is an *audit* of the production
/// recurrence, not a replacement. Surplus still does not cancel debt.
final class CognitiveDebtAuditTests: XCTestCase {

    func testFourteenNightWindowAgreesWithRecurrenceOnAllShortfalls() {
        // Newest first: 14 nights, each 60 minutes short of an 8h goal.
        let nights = [Double](repeating: 420, count: 14)
        let recursive = SleepDebtCalculator.debt(
            timeAsleepMinutesNewestFirst: nights, goalMinutes: 480
        )!
        let window = SleepDebtCalculator.weightedWindow(
            timeAsleepMinutesNewestFirst: nights, goalMinutes: 480
        )
        // Same shortfall every night, same decay: the two sums are the
        // truncated geometric series vs the infinite one. They must be
        // close, and the window (finite) must sit below the recurrence.
        XCTAssertLessThan(window, recursive)
        XCTAssertGreaterThan(window, recursive * 0.6)
    }

    func testWindowIgnoresSurplusTheSameWayTheRecurrenceDoes() {
        let nights = [600.0, 420.0] // newest: surplus, then a 60-min shortfall
        let window = SleepDebtCalculator.weightedWindow(
            timeAsleepMinutesNewestFirst: nights, goalMinutes: 480
        )
        XCTAssertGreaterThan(window, 0)
        // Surplus night contributes 0, not −120.
        let onlyShort = SleepDebtCalculator.weightedWindow(
            timeAsleepMinutesNewestFirst: [420], goalMinutes: 480
        )
        XCTAssertEqual(window, onlyShort * SleepDebtCalculator.decayPerNight, accuracy: 0.01)
    }
}

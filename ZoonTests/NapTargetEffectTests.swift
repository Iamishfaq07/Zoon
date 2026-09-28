import XCTest

/// A nap lowers tonight's target; it does not lower the shortfall.
///
/// Today took the nap off the displayed shortfall *and* off tonight's
/// target. The ledger is one-sided, so after a 60-minute nap on a 2-hour
/// shortfall Today read "1h short", the person slept the lowered target, and
/// the next morning the balance was back near 2 hours.
final class NapTargetEffectTests: XCTestCase {

    func testTheEffectIsWhatTheNapTakesOffTonightsTarget() {
        let planning = SleepPlanningInputs(
            baselineNeedMinutes: 480, currentShortfallMinutes: 120, tonightNapCreditMinutes: 60
        )
        let withoutNap = SleepPlanningInputs(baselineNeedMinutes: 480, currentShortfallMinutes: 120)
        XCTAssertEqual(planning.tonightNapEffectMinutes, 60, accuracy: 0.001)
        XCTAssertEqual(withoutNap.tonightNeedMinutes - planning.tonightNeedMinutes, 60, accuracy: 0.001)
    }

    /// The night floor limits what a long nap can do to the target.
    func testTheFloorCapsTheEffect() {
        let planning = SleepPlanningInputs(baselineNeedMinutes: 480, tonightNapCreditMinutes: 200)
        let floor = max(480 * 0.75, 480 - 120.0)
        XCTAssertEqual(planning.tonightNeedMinutes, floor, accuracy: 0.001)
        XCTAssertEqual(planning.tonightNapEffectMinutes, 480 - floor, accuracy: 0.001)
    }

    /// Sleeping the lowered target, nap included in the night's total,
    /// leaves the ledger no higher than the figure shown before the nap:
    /// nothing rebounds, because nothing was taken off it early.
    func testMeetingTheLoweredTargetDoesNotRebound() {
        let shown = 120.0
        let planning = SleepPlanningInputs(
            baselineNeedMinutes: 480, currentShortfallMinutes: shown, tonightNapCreditMinutes: 60
        )
        let next = RecentSleepShortfall.step(
            enteringMinutes: shown,
            needMinutes: 480,
            asleepMinutes: planning.tonightNeedMinutes + 60
        )
        XCTAssertLessThanOrEqual(next, shown)
    }
}

import XCTest

final class LocalSleepCorrectionTests: XCTestCase {

    func testNoRepairLeavesTheNightUntouched() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let applied = LocalSleepCorrection.apply(night, repairs: [])
        XCTAssertEqual(applied.bedtime, night.bedtime)
        XCTAssertEqual(applied.wakeTime, night.wakeTime)
        XCTAssertEqual(applied.timeAsleepMinutes, night.timeAsleepMinutes, accuracy: 0.01)
    }

    func testAnExclusionIsNotABoundaryEdit() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let repair = PersonalSetup.Repair(
            nightKey: night.nightKey,
            reason: "Watch fell off",
            excluded: true,
            bedtimeShiftMinutes: -20
        )
        let applied = LocalSleepCorrection.apply(night, repairs: [repair])
        XCTAssertEqual(applied.bedtime, night.bedtime, "an excluded night is dropped, not rewritten")
    }

    func testABedtimeShiftMovesTheWindowAndNotTheAsleepTotal() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let repair = PersonalSetup.Repair(
            nightKey: night.nightKey,
            reason: "Watch started late",
            excluded: false,
            bedtimeShiftMinutes: -20
        )
        let applied = LocalSleepCorrection.apply(night, repairs: [repair])
        XCTAssertEqual(applied.bedtime.timeIntervalSince(night.bedtime), -20 * 60, accuracy: 1)
        XCTAssertEqual(applied.timeAsleepMinutes, 450, accuracy: 0.01)
        XCTAssertEqual(applied.timeInBedMinutes, 500, accuracy: 0.5)
        XCTAssertLessThan(applied.sleepEfficiencyPercent, night.sleepEfficiencyPercent)
    }

    func testAShorterWindowClampsAsleepRatherThanInventingADeficitBeyondTheWindow() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let repair = PersonalSetup.Repair(
            nightKey: night.nightKey,
            reason: "Watch kept recording after I got up",
            excluded: false,
            wakeShiftMinutes: -60
        )
        let applied = LocalSleepCorrection.apply(night, repairs: [repair])
        XCTAssertEqual(applied.timeInBedMinutes, 420, accuracy: 0.5)
        XCTAssertEqual(applied.timeAsleepMinutes, 420, accuracy: 0.5)
        XCTAssertLessThanOrEqual(applied.timeAsleepMinutes, applied.timeInBedMinutes)
    }

    func testHealthKitOriginalsAreNotMutated() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450, timeInBedMinutes: 480)
        let originalBed = night.bedtime
        let repair = PersonalSetup.Repair(
            nightKey: night.nightKey,
            reason: "Adjusted",
            excluded: false,
            bedtimeShiftMinutes: 15
        )
        _ = LocalSleepCorrection.apply(night, repairs: [repair])
        XCTAssertEqual(night.bedtime, originalBed)
    }

    func testLegacyRepairJSONWithoutShiftsStillDecodes() throws {
        let json = """
        {"nightKey":"2026-03-01","reason":"Conflict","excluded":true}
        """.data(using: .utf8)!
        let repair = try JSONDecoder().decode(PersonalSetup.Repair.self, from: json)
        XCTAssertEqual(repair.bedtimeShiftMinutes, 0)
        XCTAssertEqual(repair.wakeShiftMinutes, 0)
        XCTAssertTrue(repair.excluded)
        XCTAssertFalse(repair.hasBoundaryEdit)
    }
}

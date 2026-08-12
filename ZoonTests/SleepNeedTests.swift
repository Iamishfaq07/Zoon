import XCTest

final class SleepNeedTests: XCTestCase {

    func testNapReducesNocturnalNeedBelowDailyBaseline() {
        let need = SleepNeed.compute(
            goalMinutes: 480,
            outstandingDebtMinutes: 0,
            yesterdayStrain: 0,
            napMinutes: 90,
            achievedMinutes: 390
        )

        XCTAssertEqual(need.totalNeedMinutes, 390, accuracy: 0.001)
        XCTAssertEqual(need.performancePercent, 100, accuracy: 0.001)
    }

    func testNapCannotReduceNightBelowSafetyFloor() {
        let need = SleepNeed.compute(
            goalMinutes: 480,
            outstandingDebtMinutes: 0,
            yesterdayStrain: 0,
            napMinutes: 300,
            achievedMinutes: 360
        )

        XCTAssertEqual(need.napCreditMinutes, 120, accuracy: 0.001)
        XCTAssertEqual(need.totalNeedMinutes, 360, accuracy: 0.001)
    }

    func testNapFirstOffsetsDebtAndStrainBonuses() {
        let need = SleepNeed(
            baselineMinutes: 480,
            debtMinutes: 60,
            strainMinutes: 30,
            napCreditMinutes: 45,
            achievedMinutes: 525
        )

        XCTAssertEqual(need.totalNeedMinutes, 525, accuracy: 0.001)
    }
}

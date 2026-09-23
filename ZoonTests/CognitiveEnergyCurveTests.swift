import XCTest

final class CognitiveEnergyCurveTests: XCTestCase {

    func testProducesOnePointPerWakingHour() {
        let curve = CognitiveEnergyCurve.compute(
            wakeTime: Date(),
            hourCount: 16,
            hrvSDNN: 60, hrvBaseline: 60,
            restingHeartRate: 56, minOvernightHeartRate: 48,
            remMinutes: 100, deepMinutes: 80, asleepMinutes: 450,
            sleepDebtMinutes: 0
        )
        XCTAssertEqual(curve.hours.count, 16)
        XCTAssertTrue(curve.missing.isEmpty)
    }

    func testHighHRVRaisesThePeakRelativeToLowHRV() {
        let high = CognitiveEnergyCurve.compute(
            wakeTime: Date(), hourCount: 16,
            hrvSDNN: 80, hrvBaseline: 60,
            restingHeartRate: 56, minOvernightHeartRate: 48,
            remMinutes: 100, deepMinutes: 80, asleepMinutes: 450,
            sleepDebtMinutes: 0
        )
        let low = CognitiveEnergyCurve.compute(
            wakeTime: Date(), hourCount: 16,
            hrvSDNN: 40, hrvBaseline: 60,
            restingHeartRate: 56, minOvernightHeartRate: 48,
            remMinutes: 100, deepMinutes: 80, asleepMinutes: 450,
            sleepDebtMinutes: 0
        )
        let highPeak = high.hours.map(\.level).max() ?? 0
        let lowPeak = low.hours.map(\.level).max() ?? 0
        XCTAssertGreaterThan(highPeak, lowPeak)
    }

    func testDebtAttenuatesAmplitude() {
        let fresh = CognitiveEnergyCurve.compute(
            wakeTime: Date(), hourCount: 16,
            hrvSDNN: 60, hrvBaseline: 60,
            restingHeartRate: 56, minOvernightHeartRate: 48,
            remMinutes: 100, deepMinutes: 80, asleepMinutes: 450,
            sleepDebtMinutes: 0
        )
        let indebted = CognitiveEnergyCurve.compute(
            wakeTime: Date(), hourCount: 16,
            hrvSDNN: 60, hrvBaseline: 60,
            restingHeartRate: 56, minOvernightHeartRate: 48,
            remMinutes: 100, deepMinutes: 80, asleepMinutes: 450,
            sleepDebtMinutes: 240
        )
        XCTAssertGreaterThan(
            fresh.hours.map(\.level).max() ?? 0,
            indebted.hours.map(\.level).max() ?? 0
        )
    }

    func testMissingHRVIsReportedNotInvented() {
        let curve = CognitiveEnergyCurve.compute(
            wakeTime: Date(), hourCount: 14,
            hrvSDNN: nil, hrvBaseline: nil,
            restingHeartRate: nil, minOvernightHeartRate: nil,
            remMinutes: 0, deepMinutes: 0, asleepMinutes: 0,
            sleepDebtMinutes: 0
        )
        XCTAssertTrue(curve.missing.contains("HRV"))
        XCTAssertTrue(curve.missing.contains("overnight HR dip"))
        XCTAssertTrue(curve.missing.contains("sleep stages"))
    }

    func testAfternoonSlumpSitsNearSevenHoursAwake() {
        let dip = CognitiveEnergyCurve.twoProcessShape(hoursAwake: 7.5)
        let peak = CognitiveEnergyCurve.twoProcessShape(hoursAwake: 3.5)
        XCTAssertGreaterThan(peak, dip)
    }

    func testHourCountIsClamped() {
        let short = CognitiveEnergyCurve.compute(
            wakeTime: Date(), hourCount: 4,
            hrvSDNN: 60, hrvBaseline: 60,
            restingHeartRate: 56, minOvernightHeartRate: 48,
            remMinutes: 90, deepMinutes: 70, asleepMinutes: 400,
            sleepDebtMinutes: 0
        )
        XCTAssertEqual(short.hours.count, 12)
    }

    /// A duration-only night: seven hours asleep, nothing staged. Zero REM
    /// and zero deep are unmeasured, not observed, and must not pull the
    /// whole curve down.
    func testADurationOnlyNightIsNotPenalised() {
        let wake = Date(timeIntervalSince1970: 1_700_000_000)
        func curve(rem: Double, deep: Double, core: Double) -> CognitiveEnergyCurve {
            CognitiveEnergyCurve.compute(
                wakeTime: wake, hrvSDNN: nil, hrvBaseline: nil, restingHeartRate: nil,
                minOvernightHeartRate: nil, remMinutes: rem, deepMinutes: deep,
                asleepMinutes: 420, sleepDebtMinutes: 0, coreMinutes: core
            )
        }
        let unstaged = curve(rem: 0, deep: 0, core: 0)
        let neutral = CognitiveEnergyCurve.compute(
            wakeTime: wake, hrvSDNN: nil, hrvBaseline: nil, restingHeartRate: nil,
            minOvernightHeartRate: nil, remMinutes: 0, deepMinutes: 0,
            asleepMinutes: 0, sleepDebtMinutes: 0
        )
        XCTAssertTrue(unstaged.missing.contains("sleep stages"))
        XCTAssertEqual(unstaged.hours.map(\.level), neutral.hours.map(\.level),
                       "an unstaged night reads exactly like no stage data")

        // A partly staged night (half the time classified) is not enough
        // coverage to judge the mix either.
        XCTAssertTrue(curve(rem: 40, deep: 30, core: 140).missing.contains("sleep stages"))
        // A fully staged night is.
        XCTAssertFalse(curve(rem: 90, deep: 70, core: 260).missing.contains("sleep stages"))
    }
}

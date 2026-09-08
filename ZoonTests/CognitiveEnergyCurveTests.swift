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
}

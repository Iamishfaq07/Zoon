import XCTest

final class BodyBatteryTests: XCTestCase {

    // MARK: - overnightCharge

    func testOvernightChargeNeverDropsBelowTheFloor() {
        let charge = BodyBattery.overnightCharge(recoveryPercent: 0, sleepPerformance: 0)
        XCTAssertEqual(charge, 25, accuracy: 0.001)
    }

    func testOvernightChargeReachesFullOnPerfectInputs() {
        let charge = BodyBattery.overnightCharge(recoveryPercent: 100, sleepPerformance: 100)
        XCTAssertEqual(charge, 100, accuracy: 0.001)
    }

    func testOvernightChargeWeighsRecoveryMoreThanSleepPerformance() {
        // Same average (50), but recovery-heavy should score higher since
        // recovery is weighted 0.6 vs sleep's 0.4.
        let recoveryHeavy = BodyBattery.overnightCharge(recoveryPercent: 80, sleepPerformance: 20)
        let sleepHeavy = BodyBattery.overnightCharge(recoveryPercent: 20, sleepPerformance: 80)
        XCTAssertGreaterThan(recoveryHeavy, sleepHeavy)
    }

    func testOvernightChargeClampsSleepPerformanceAboveOneHundred() {
        // sleepPerformance can exceed 100 (over-sleeping past goal); the
        // formula clamps it via min(1, sleepPerformance / 100).
        let clamped = BodyBattery.overnightCharge(recoveryPercent: 50, sleepPerformance: 150)
        let atCap = BodyBattery.overnightCharge(recoveryPercent: 50, sleepPerformance: 100)
        XCTAssertEqual(clamped, atCap, accuracy: 0.001)
    }

    // MARK: - build

    func testBuildWithNoHeartRateSamplesReturnsFlatStartLevel() {
        let battery = BodyBattery.build(
            startLevel: 72,
            wakeTime: .now,
            hourlyHeartRate: [],
            restingHeartRate: 55,
            maxHeartRate: 180
        )
        XCTAssertEqual(battery.current, 72)
        XCTAssertEqual(battery.morningPeak, 72)
        XCTAssertEqual(battery.dayLow, 72)
        XCTAssertEqual(battery.points.count, 1)
    }

    func testBuildDrainsWhenHeartRateIsWellAboveResting() {
        let wake = Date.now
        let battery = BodyBattery.build(
            startLevel: 80,
            wakeTime: wake,
            hourlyHeartRate: [(date: wake.addingTimeInterval(3600), bpm: 150)],
            restingHeartRate: 55,
            maxHeartRate: 180
        )
        XCTAssertLessThan(battery.current, 80)
        XCTAssertFalse(battery.points.last!.isCharging)
    }

    func testBuildChargesWhenHeartRateIsAtRestingWhileAwake() {
        let wake = Date.now
        let battery = BodyBattery.build(
            startLevel: 50,
            wakeTime: wake,
            hourlyHeartRate: [(date: wake.addingTimeInterval(3600), bpm: 55)],
            restingHeartRate: 55,
            maxHeartRate: 180
        )
        XCTAssertGreaterThan(battery.current, 50)
        XCTAssertTrue(battery.points.last!.isCharging)
    }

    func testBuildIgnoresSamplesBeforeWakeTime() {
        let wake = Date.now
        let battery = BodyBattery.build(
            startLevel: 60,
            wakeTime: wake,
            hourlyHeartRate: [(date: wake.addingTimeInterval(-3600), bpm: 160)],
            restingHeartRate: 55,
            maxHeartRate: 180
        )
        // The only sample predates wake, so it's filtered out and the curve
        // is just the flat starting point.
        XCTAssertEqual(battery.points.count, 1)
        XCTAssertEqual(battery.current, 60)
    }

    func testBuildClampsLevelToZeroAndOneHundred() {
        let wake = Date.now
        let samples = (1...20).map { hour in
            (date: wake.addingTimeInterval(Double(hour) * 3600), bpm: 178.0)
        }
        let battery = BodyBattery.build(
            startLevel: 30,
            wakeTime: wake,
            hourlyHeartRate: samples,
            restingHeartRate: 55,
            maxHeartRate: 180
        )
        XCTAssertGreaterThanOrEqual(battery.dayLow, 0)
        XCTAssertLessThanOrEqual(battery.morningPeak, 100)
    }

    // MARK: - band / guidance / spentToday

    func testBandBoundaries() {
        XCTAssertEqual(BodyBattery(points: [], current: 0, morningPeak: 0, dayLow: 0).band, "Low")
        XCTAssertEqual(BodyBattery(points: [], current: 24, morningPeak: 0, dayLow: 0).band, "Low")
        XCTAssertEqual(BodyBattery(points: [], current: 25, morningPeak: 0, dayLow: 0).band, "Moderate")
        XCTAssertEqual(BodyBattery(points: [], current: 49, morningPeak: 0, dayLow: 0).band, "Moderate")
        XCTAssertEqual(BodyBattery(points: [], current: 50, morningPeak: 0, dayLow: 0).band, "Good")
        XCTAssertEqual(BodyBattery(points: [], current: 74, morningPeak: 0, dayLow: 0).band, "Good")
        XCTAssertEqual(BodyBattery(points: [], current: 75, morningPeak: 0, dayLow: 0).band, "High")
        XCTAssertEqual(BodyBattery(points: [], current: 100, morningPeak: 0, dayLow: 0).band, "High")
    }

    func testSpentTodayNeverGoesNegative() {
        // current above morningPeak (a charging day) should read as 0 spent,
        // not a negative number.
        let battery = BodyBattery(points: [], current: 80, morningPeak: 70, dayLow: 60)
        XCTAssertEqual(battery.spentToday, 0)
    }

    func testSpentTodayIsTheDropFromMorningPeak() {
        let battery = BodyBattery(points: [], current: 40, morningPeak: 70, dayLow: 35)
        XCTAssertEqual(battery.spentToday, 30)
    }
}

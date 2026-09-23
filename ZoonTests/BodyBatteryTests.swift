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
            maxHeartRate: 180,
            // Buckets are stamped at their start, so the bucket beginning an
            // hour after waking is observed only once that hour has passed.
            now: wake.addingTimeInterval(3 * 3600)
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
            maxHeartRate: 180,
            now: wake.addingTimeInterval(3 * 3600)
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
            maxHeartRate: 180,
            now: wake.addingTimeInterval(22 * 3600)
        )
        XCTAssertGreaterThanOrEqual(battery.dayLow, 0)
        XCTAssertLessThanOrEqual(battery.morningPeak, 100)
    }

    func testOvernightOnlyDoesNotInventDaytimeDrain() {
        let wake = Date.now
        let battery = BodyBattery.overnightOnly(startLevel: 64, wakeTime: wake)
        XCTAssertEqual(battery.points.count, 1)
        XCTAssertEqual(battery.current, 64)
        XCTAssertEqual(battery.restingBaselineSource, .unavailable)
        XCTAssertTrue(battery.isEstimate)
        XCTAssertNotNil(battery.confidenceNote)
    }

    func testPersonalBaselineIsMarkedPersonalized() {
        let wake = Date.now
        var battery = BodyBattery.build(
            startLevel: 64,
            wakeTime: wake,
            hourlyHeartRate: [],
            restingHeartRate: 54,
            maxHeartRate: 180,
            restingBaselineSource: .personalBaseline
        )
        // `build` cannot know what charged the battery -- `DayContextBuilder`
        // assigns provenance from Recovery afterwards -- so it has to be said
        // here too, or the fixture is a personal drawdown hanging off a
        // charge that came from nowhere.
        battery.provenance = .fullPhysiologicalRecovery

        XCTAssertFalse(battery.isEstimate)
        XCTAssertNil(battery.confidenceNote)
    }

    /// The drawdown being personal does not excuse the charge. Energy that
    /// started from sleep alone says so even when the resting baseline is the
    /// user's own.
    func testAPersonalBaselineDoesNotSilenceAnUngroundedCharge() throws {
        var battery = BodyBattery.build(
            startLevel: 64,
            wakeTime: .now,
            hourlyHeartRate: [],
            restingHeartRate: 54,
            maxHeartRate: 180,
            restingBaselineSource: .personalBaseline
        )
        battery.provenance = .sleepDerivedEstimate

        let note = try XCTUnwrap(battery.confidenceNote)
        XCTAssertTrue(note.lowercased().contains("sleep alone"))
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

    // MARK: - Integration over observed time (Z11)

    private func clock(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: hour, minute: minute))!
    }

    /// Wake at 07:10. The 07:00 bucket is 50 minutes of the day, not none:
    /// it used to be dropped for starting before the wake.
    func testABucketThatStartsBeforeWakeCountsForItsWakingPart() {
        let battery = BodyBattery.build(
            startLevel: 80, wakeTime: clock(7, 10),
            hourlyHeartRate: [(date: clock(7, 0), bpm: 150)],
            restingHeartRate: 55, maxHeartRate: 180, now: clock(9, 0)
        )
        XCTAssertLessThan(battery.current, 80)
        XCTAssertEqual(battery.observedDaytimeHours ?? 0, 50.0 / 60, accuracy: 0.001)
    }

    /// One reading in the 08:00 bucket at 08:05 is five minutes observed,
    /// not an hour of effort.
    func testABucketInProgressCountsOnlyUpToNow() {
        let partial = BodyBattery.build(
            startLevel: 80, wakeTime: clock(7, 10),
            hourlyHeartRate: [(date: clock(8, 0), bpm: 150)],
            restingHeartRate: 55, maxHeartRate: 180, now: clock(8, 5)
        )
        let whole = BodyBattery.build(
            startLevel: 80, wakeTime: clock(7, 10),
            hourlyHeartRate: [(date: clock(8, 0), bpm: 150)],
            restingHeartRate: 55, maxHeartRate: 180, now: clock(10, 0)
        )
        let partialDrop = 80 - (partial.points.last?.level ?? 80)
        let wholeDrop = 80 - (whole.points.last?.level ?? 80)
        XCTAssertEqual(partialDrop * 12, wholeDrop, accuracy: 0.01)
    }

    /// A missing afternoon is a gap, not rest, and it lowers confidence.
    func testAMissingAfternoonIsNotChargedAsRest() {
        let morning = (8...11).map { (date: clock($0, 0), bpm: 70.0) }
        let battery = BodyBattery.build(
            startLevel: 70, wakeTime: clock(7, 0),
            hourlyHeartRate: morning,
            restingHeartRate: 55, maxHeartRate: 180, now: clock(19, 0)
        )
        XCTAssertEqual(battery.observedDaytimeHours ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(battery.elapsedDaytimeHours ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(battery.lastObservedAt, clock(12, 0))
        var withProvenance = battery
        withProvenance.provenance = .fullPhysiologicalRecovery
        XCTAssertLessThan(withProvenance.confidence, .high)
        XCTAssertTrue(withProvenance.confidenceNote?.contains("4 of 12") ?? false, withProvenance.confidenceNote ?? "")
    }

    /// No heart rate all day: the curve is last night's charge, and says so.
    func testAllDayWithoutDataSaysSo() {
        var battery = BodyBattery.build(
            startLevel: 70, wakeTime: clock(7, 0), hourlyHeartRate: [],
            restingHeartRate: 55, maxHeartRate: 180, now: clock(19, 0)
        )
        battery.provenance = .fullPhysiologicalRecovery
        XCTAssertEqual(battery.confidence, .low)
        XCTAssertTrue(battery.confidenceNote?.contains("No heart rate since you woke") ?? false)
    }
}

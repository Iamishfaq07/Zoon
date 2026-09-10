import XCTest

final class SleepFingerprintTests: XCTestCase {
    func testFingerprintNeedsThreeNights() {
        XCTAssertNil(SleepFingerprint.make(from: [], days: 30))
    }

    func testStableNightsProduceHighContinuity() {
        let nights = (0..<5).map { index in
            SleepNightFeatures(date: Date().addingTimeInterval(Double(index) * 86_400), bedtime: Date(), wakeTime: Date(), timeInBedMinutes: 480, timeAsleepMinutes: 450, sleepEfficiencyPercent: 94, coreMinutes: 260, deepMinutes: 90, remMinutes: 100, unspecifiedAsleepMinutes: 0, awakeMinutes: 30, wakeCount: 1, sleepLatencyMinutes: nil, avgHeartRate: 55, minHeartRate: 50, restingHeartRate: 52, avgHRV: 55, avgRespiratoryRate: 14, avgSpO2: nil, wristTempDeltaC: nil, hrv7DayAvg: 55, sleepDebtMinutes: 0, lastWorkoutHoursBeforeBed: nil, exerciseMinutesPreviousDay: nil, sourceName: "Test")
        }
        let result = SleepFingerprint.make(from: nights, days: 30)
        XCTAssertEqual(result?.sampleCount, 5)
        XCTAssertGreaterThan(result?.continuity ?? 0, 0.9)
    }

    func testCircularDispersionTreatsMidnightClusterAsStable() {
        let mad = Statistics.circularMedianAbsoluteDeviation([1435, 0, 5])
        XCTAssertEqual(mad ?? .nan, 5, accuracy: 0.001)
    }

    func testCircularDispersionTreatsDaySleeperAsStable() {
        let mad = Statistics.circularMedianAbsoluteDeviation([540, 550, 535])
        XCTAssertEqual(mad ?? .nan, 5, accuracy: 0.001)
    }

    /// 23:00 against 11:00 -- half a day apart on the clock circle. The
    /// medoid centre lands on one of the two, so the median distance is
    /// twelve hours halved: 360 minutes. (23:00 against 03:00, the old
    /// fixture, is only four hours apart and correctly reads 120.)
    func testCircularDispersionTreatsOppositeScheduleAsVariable() {
        let mad = Statistics.circularMedianAbsoluteDeviation([1380, 660])
        XCTAssertGreaterThan(mad ?? 0, 200)
    }

    /// No HRV at all is no reading, not an unstable one. The value stays a
    /// placeholder for the view's sake, and the flag says so.
    func testMissingHRVIsFlaggedAsUnmeasuredRatherThanUnstable() throws {
        func nights(hrv: Double?) -> [SleepNightFeatures] {
            (0..<5).map { index in
                SleepNightFeatures(date: Date().addingTimeInterval(Double(index) * 86_400), bedtime: Date(), wakeTime: Date(), timeInBedMinutes: 480, timeAsleepMinutes: 450, sleepEfficiencyPercent: 94, coreMinutes: 260, deepMinutes: 90, remMinutes: 100, unspecifiedAsleepMinutes: 0, awakeMinutes: 30, wakeCount: 1, sleepLatencyMinutes: nil, avgHeartRate: 55, minHeartRate: 50, restingHeartRate: 52, avgHRV: hrv, avgRespiratoryRate: 14, avgSpO2: nil, wristTempDeltaC: nil, hrv7DayAvg: hrv, sleepDebtMinutes: 0, lastWorkoutHoursBeforeBed: nil, exerciseMinutesPreviousDay: nil, sourceName: "Test")
            }
        }
        let unmeasured = try XCTUnwrap(SleepFingerprint.make(from: nights(hrv: nil), days: 30))
        XCTAssertFalse(unmeasured.bodySignalStabilityIsMeasured)

        let measured = try XCTUnwrap(SleepFingerprint.make(from: nights(hrv: 55), days: 30))
        XCTAssertTrue(measured.bodySignalStabilityIsMeasured)
    }

    // MARK: - SleepEras

    /// An even-sized era whose bedtimes straddle midnight (23:50 / 00:10)
    /// must report a median bedtime at midnight -- not noon, which is what
    /// averaging the two middle values on a linear 0..1439 scale produced.
    func testEraMedianBedtimeStraddlingMidnightIsNotNoon() throws {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 2
        components.hour = 7
        let firstWake = try XCTUnwrap(calendar.date(from: components))

        let nights = (0..<8).map { index -> SleepNightFeatures in
            let wake = firstWake.addingTimeInterval(Double(index) * 86_400)
            // Alternate 23:50 the evening before and 00:10 the same morning.
            let bedtime = wake.addingTimeInterval(index.isMultiple(of: 2) ? -(7 * 60 + 10) * 60 : -(6 * 60 + 50) * 60)
            return SleepNightFeatures(date: wake, bedtime: bedtime, wakeTime: wake, timeInBedMinutes: 420, timeAsleepMinutes: 400, sleepEfficiencyPercent: 95, coreMinutes: 230, deepMinutes: 80, remMinutes: 90, unspecifiedAsleepMinutes: 0, awakeMinutes: 20, wakeCount: 1, sleepLatencyMinutes: nil, avgHeartRate: 55, minHeartRate: 50, restingHeartRate: 52, avgHRV: 55, avgRespiratoryRate: 14, avgSpO2: nil, wristTempDeltaC: nil, hrv7DayAvg: 55, sleepDebtMinutes: 0, lastWorkoutHoursBeforeBed: nil, exerciseMinutesPreviousDay: nil, sourceName: "Test")
        }

        let eras = SleepEras.detect(in: nights)
        XCTAssertEqual(eras.count, 1, "twenty minutes of alternation is not an era change")
        let median = try XCTUnwrap(eras.first?.medianBedtime)
        XCTAssertEqual(calendar.component(.hour, from: median), 0)
        XCTAssertEqual(calendar.component(.minute, from: median), 0)
    }
}

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
        XCTAssertEqual(mad, 5, accuracy: 0.001)
    }

    func testCircularDispersionTreatsDaySleeperAsStable() {
        let mad = Statistics.circularMedianAbsoluteDeviation([540, 550, 535])
        XCTAssertEqual(mad, 5, accuracy: 0.001)
    }

    func testCircularDispersionTreatsOppositeScheduleAsVariable() {
        let mad = Statistics.circularMedianAbsoluteDeviation([1380, 180])
        XCTAssertGreaterThan(mad ?? 0, 200)
    }
}

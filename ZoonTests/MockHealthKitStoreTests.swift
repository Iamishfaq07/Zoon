import HealthKit
import XCTest

final class MockHealthKitStoreTests: XCTestCase {

    func testATypicalNightProducesABuildableSession() {
        let wake = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 7))!
        let samples = MockHealthKitStore.sleepAnalysisSamples(for: .typical(wakeDate: wake))
        XCTAssertFalse(samples.isEmpty)

        let sessions = SleepSessionBuilder().buildSessions(from: samples)
        XCTAssertEqual(sessions.count, 1)
        guard let session = sessions.first else { return }
        XCTAssertGreaterThan(session.totalAsleepMinutes, 60)
        XCTAssertLessThan(session.totalAsleepMinutes, 12 * 60)
        XCTAssertTrue(session.stageMinutes[.deep, default: 0] > 0)
        XCTAssertTrue(session.stageMinutes[.rem, default: 0] > 0)
    }

    func testUnspecifiedSourceStillCountsAsSleep() {
        let wake = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 7))!
        var spec = MockHealthKitStore.NightSpec.typical(wakeDate: wake)
        spec.includeStages = false
        let samples = MockHealthKitStore.sleepAnalysisSamples(for: spec)
        let sessions = SleepSessionBuilder().buildSessions(from: samples)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertGreaterThan(sessions.first?.totalAsleepMinutes ?? 0, 0)
    }

    func testQuantityStreamsCoverTheNight() {
        let interval = DateInterval(start: Date(), duration: 8 * 3600)
        XCTAssertFalse(MockHealthKitStore.heartRateSamples(in: interval).isEmpty)
        XCTAssertFalse(MockHealthKitStore.hrvSamples(in: interval).isEmpty)
        XCTAssertFalse(MockHealthKitStore.oxygenSamples(in: interval).isEmpty)
        XCTAssertFalse(MockHealthKitStore.wristTemperatureSamples(in: interval).isEmpty)
        XCTAssertFalse(MockHealthKitStore.respiratorySamples(in: interval).isEmpty)
        XCTAssertFalse(MockHealthKitStore.breathingDisturbanceSamples(in: interval).isEmpty)
    }

    func testNightStreamsAreInternallyConsistent() {
        let wake = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 7))!
        let streams = MockHealthKitStore.nightStreams(wakeDate: wake)
        XCTAssertFalse(streams.sleep.isEmpty)
        XCTAssertFalse(streams.heartRate.isEmpty)
        guard let start = streams.sleep.map(\.startDate).min(),
              let end = streams.sleep.map(\.endDate).max() else {
            return XCTFail("sleep stream had no span")
        }
        for sample in streams.heartRate {
            XCTAssertGreaterThanOrEqual(sample.startDate, start.addingTimeInterval(-1))
            XCTAssertLessThanOrEqual(sample.endDate, end.addingTimeInterval(1))
        }
    }
}

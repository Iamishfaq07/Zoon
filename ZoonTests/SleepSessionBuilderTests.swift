import XCTest
import HealthKit

/// `HKCategorySample`'s convenience initializers can't set a custom
/// `sourceRevision` (there's no public API for that on an unsaved sample --
/// it's always synthesized from the running process), so the per-cluster
/// multi-source selection fix in `SleepSessionBuilder.preferredSourceSamples`
/// isn't mechanically unit-testable here: every sample built in-process
/// reports the same source, so the "which source wins" branch never
/// activates. What *is* testable, and what these tests cover, is the
/// session-clustering and short-session-preservation behavior around it --
/// the other half of this session's fix, and the one most likely to regress
/// silently if `minimumSessionDuration` or the gap threshold ever moves
/// again.
final class SleepSessionBuilderTests: XCTestCase {

    private let calendar = Calendar.current

    private func sample(_ stage: HKCategoryValueSleepAnalysis, start: Date, end: Date) -> HKCategorySample {
        HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: stage.rawValue, start: start, end: end)
    }

    func testTwoNightsSeparatedByADayAreDistinctSessions() {
        let night1Start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!
        let night1End = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7))!
        let night2Start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 23))!
        let night2End = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 7))!

        let samples = [
            sample(.asleepCore, start: night1Start, end: night1End),
            sample(.asleepCore, start: night2Start, end: night2End)
        ]

        let builder = SleepSessionBuilder()
        let sessions = builder.buildSessions(from: samples)

        XCTAssertEqual(sessions.count, 2)
    }

    /// The exact regression this session's fix targets: a real short night
    /// (or nap) used to vanish entirely below the old 2-hour floor. It must
    /// now survive as long as it clears the genuine noise floor.
    func testShortButRealSessionIsPreservedNotDiscarded() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 14))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 14, minute: 45))!

        let builder = SleepSessionBuilder()
        let sessions = builder.buildSessions(from: [sample(.asleepCore, start: start, end: end)])

        guard let session = sessions.first else {
            return XCTFail("Expected the 45-minute session to survive filtering")
        }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(session.timeInBed, 45 * 60, accuracy: 1)
    }

    func testSessionBelowNoiseFloorIsDiscarded() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 14))!
        let end = start.addingTimeInterval(5 * 60) // 5 minutes -- below the 15-minute floor

        let builder = SleepSessionBuilder()
        let sessions = builder.buildSessions(from: [sample(.asleepCore, start: start, end: end)])

        XCTAssertTrue(sessions.isEmpty)
    }

    func testGapWithinThresholdStaysOneSession() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!
        let bathroomBreakStart = start.addingTimeInterval(3 * 3600)
        let bathroomBreakEnd = bathroomBreakStart.addingTimeInterval(20 * 60) // 20 min gap, under the 60-min threshold
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7))!

        let samples = [
            sample(.asleepCore, start: start, end: bathroomBreakStart),
            sample(.asleepCore, start: bathroomBreakEnd, end: end)
        ]

        let builder = SleepSessionBuilder()
        let sessions = builder.buildSessions(from: samples)

        XCTAssertEqual(sessions.count, 1, "A short gap inside one night must not split it into two sessions")
    }

    /// The exact distinction `SleepNightFeatures.timeInBedIsEstimated`
    /// depends on: Apple Watch alone writes no `inBed` samples, so
    /// `timeInBed` there is the asleep/awake span standing in for a real
    /// measurement, not one.
    func testSessionWithoutInBedSamplesIsNotExplicitInBedData() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7))!

        let builder = SleepSessionBuilder()
        guard let session = builder.buildSessions(from: [sample(.asleepCore, start: start, end: end)]).first else {
            return XCTFail("Expected one session")
        }

        XCTAssertFalse(session.hasExplicitInBedData)
    }

    func testSessionWithInBedSamplesIsExplicitInBedData() {
        let bedStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 22, minute: 30))!
        let onset = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7))!

        let samples = [
            sample(.inBed, start: bedStart, end: end),
            sample(.asleepCore, start: onset, end: end)
        ]

        let builder = SleepSessionBuilder()
        guard let session = builder.buildSessions(from: samples).first else {
            return XCTFail("Expected one session")
        }

        XCTAssertTrue(session.hasExplicitInBedData)
    }

    func testWakeCountOnlyCountsAwakeningsAfterSleepOnset() {
        let bedStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 22))!
        let restlessBeforeSleep = bedStart.addingTimeInterval(10 * 60)
        let onset = bedStart.addingTimeInterval(20 * 60)
        let midNightWake = onset.addingTimeInterval(3 * 3600)
        let backToSleep = midNightWake.addingTimeInterval(10 * 60)
        let wakeUp = onset.addingTimeInterval(8 * 3600)

        let samples = [
            sample(.inBed, start: bedStart, end: wakeUp),
            sample(.awake, start: restlessBeforeSleep, end: onset),
            sample(.asleepCore, start: onset, end: midNightWake),
            sample(.awake, start: midNightWake, end: backToSleep),
            sample(.asleepCore, start: backToSleep, end: wakeUp)
        ]

        let builder = SleepSessionBuilder()
        guard let session = builder.buildSessions(from: samples).first else {
            return XCTFail("Expected one session")
        }

        XCTAssertEqual(session.wakeCountAfterOnset, 1, "The restless period before onset must not count as an awakening")
    }

    /// Wearable stage classification flickers -- a single movement can emit a
    /// sub-minute `awake` sample the sleeper never experienced. Those must not
    /// be scored as fragmentation, but must still be drawn on the hypnogram.
    func testSubThresholdFlickerIsNotAMeaningfulAwakening() {
        let onset = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!
        let flickerStart = onset.addingTimeInterval(2 * 3600)
        let flickerEnd = flickerStart.addingTimeInterval(30)
        let wakeUp = onset.addingTimeInterval(8 * 3600)

        let samples = [
            sample(.asleepCore, start: onset, end: flickerStart),
            sample(.awake, start: flickerStart, end: flickerEnd),
            sample(.asleepCore, start: flickerEnd, end: wakeUp)
        ]

        let builder = SleepSessionBuilder()
        guard let session = builder.buildSessions(from: samples).first else {
            return XCTFail("Expected one session")
        }

        XCTAssertEqual(session.wakeCountAfterOnset, 0, "A 30-second flicker is not an awakening")
        // The raw picture is preserved for the hypnogram and any view that
        // wants it -- this fix filters the scored count, it doesn't discard data.
        XCTAssertEqual(session.rawAwakeningCountAfterOnset, 1)
        XCTAssertEqual(session.awakeIntervals.count, 1)
    }

    func testAwakeningAtTheThresholdCounts() {
        let onset = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!
        let wakeStart = onset.addingTimeInterval(2 * 3600)
        let wakeEnd = wakeStart.addingTimeInterval(SleepSession.meaningfulAwakeningThreshold)
        let wakeUp = onset.addingTimeInterval(8 * 3600)

        let samples = [
            sample(.asleepCore, start: onset, end: wakeStart),
            sample(.awake, start: wakeStart, end: wakeEnd),
            sample(.asleepCore, start: wakeEnd, end: wakeUp)
        ]

        let builder = SleepSessionBuilder()
        guard let session = builder.buildSessions(from: samples).first else {
            return XCTFail("Expected one session")
        }

        XCTAssertEqual(session.wakeCountAfterOnset, 1)
    }
}

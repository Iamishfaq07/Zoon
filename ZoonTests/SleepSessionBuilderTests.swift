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

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.timeInBed, 45 * 60, accuracy: 1)
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
}

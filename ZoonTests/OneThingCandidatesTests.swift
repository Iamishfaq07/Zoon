import XCTest

final class OneThingCandidatesTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testAShortNightProducesAProtectWindowCandidate() throws {
        let nights = (1...14).map {
            Fixture.night(daysAgo: $0, timeInBedMinutes: 480, bedtimeHour: 23,
                          timeZoneIdentifier: "UTC")
        }
        let sleepNeed = SleepNeed.compute(
            goalMinutes: 480, outstandingDebtMinutes: 180,
            yesterdayStrain: 0, napMinutes: 0, achievedMinutes: 400
        )
        // Mid-afternoon, with tonight's window ahead. This used 06:13, inside
        // the 23:00-07:00 night, where the only candidate was a "skip a nap,
        // bedtime is too close" about a bedtime seven hours gone.
        let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let now = try XCTUnwrap(calendar.date(bySettingHour: 14, minute: 0, second: 0, of: reference))
        let tonight = TonightPlanner.build(
            nights: nights,
            sleepNeed: sleepNeed,
            outstandingShortfallMinutes: 180,
            lastWake: nights[0].wakeTime,
            now: now,
            calendar: calendar
        )
        let nap = NapCoach.recommend(
            now: now,
            debtMinutes: 180,
            plannedBedtime: tonight.bedtime(now: now, calendar: calendar),
            napMinutesToday: 0
        )
        let recovery = RecoveryScore.compute(
            features: Fixture.night(),
            baseline: RecoveryBaseline.from(nights: nights),
            sleepPerformance: 80
        )
        let candidates = OneThingCandidates.gather(
            tonight: tonight,
            nap: nap,
            recovery: recovery,
            now: now,
            caffeineCutoff: nil
        )
        XCTAssertFalse(candidates.isEmpty)
        // Unwrapped, not forced: a nil here used to crash the test process
        // and take every test after it down too.
        let selection = try XCTUnwrap(OneThing.choose(from: candidates))
        XCTAssertFalse(selection.candidate.action.isEmpty)
        XCTAssertFalse(selection.candidate.reason.isEmpty)
    }

    /// Inside the planned night there is nothing to do, and a bedtime
    /// already behind now is not "too close".
    func testNoSkipNapAdviceAboutABedtimeAlreadyPassed() throws {
        let nights = (1...14).map {
            Fixture.night(daysAgo: $0, timeInBedMinutes: 480, bedtimeHour: 23,
                          timeZoneIdentifier: "UTC")
        }
        let sleepNeed = SleepNeed.compute(
            goalMinutes: 480, outstandingDebtMinutes: 180,
            yesterdayStrain: 0, napMinutes: 0, achievedMinutes: 400
        )
        let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let now = try XCTUnwrap(calendar.date(bySettingHour: 6, minute: 13, second: 0, of: reference))
        let tonight = TonightPlanner.build(
            nights: nights, sleepNeed: sleepNeed, outstandingShortfallMinutes: 180,
            lastWake: nights[0].wakeTime, now: now, calendar: calendar
        )
        let nap = NapCoach.recommend(
            now: now, debtMinutes: 180,
            plannedBedtime: tonight.bedtime(now: now, calendar: calendar), napMinutesToday: 0
        )
        let candidates = OneThingCandidates.gather(
            tonight: tonight, nap: nap,
            recovery: RecoveryScore.compute(
                features: Fixture.night(), baseline: RecoveryBaseline.from(nights: nights), sleepPerformance: 80
            ),
            now: now, caffeineCutoff: nil
        )
        XCTAssertFalse(candidates.contains { $0.kind == .skipLateNap })
    }
}

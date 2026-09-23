import XCTest

final class OneThingCandidatesTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testAShortNightProducesAProtectWindowCandidate() {
        let nights = (1...14).map {
            Fixture.night(daysAgo: $0, timeInBedMinutes: 480, bedtimeHour: 23,
                          timeZoneIdentifier: "UTC")
        }
        let sleepNeed = SleepNeed.compute(
            goalMinutes: 480, outstandingDebtMinutes: 180,
            yesterdayStrain: 0, napMinutes: 0, achievedMinutes: 400
        )
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
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
        let selection = OneThing.choose(from: candidates)
        XCTAssertNotNil(selection)
        XCTAssertFalse(selection!.candidate.action.isEmpty)
        XCTAssertFalse(selection!.candidate.reason.isEmpty)
    }
}

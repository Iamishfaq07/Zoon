import XCTest

/// §6 / §7. One synthetic day, every Tonight consumer reads the same plan,
/// and the shortfall is repaid exactly once.
final class TonightPlanTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func history() -> [SleepNightFeatures] {
        (1...14).map {
            Fixture.night(
                daysAgo: $0,
                timeInBedMinutes: 480,
                bedtimeHour: 23,
                timeZoneIdentifier: "UTC"
            )
        }
    }

    private func need(
        outstandingShortfall: Double,
        yesterdayStrain: Double = 0,
        napMinutes: Double = 0
    ) -> SleepNeed {
        SleepNeed.compute(
            goalMinutes: 480,
            outstandingDebtMinutes: outstandingShortfall,
            yesterdayStrain: yesterdayStrain,
            napMinutes: napMinutes,
            achievedMinutes: 400
        )
    }

    private func plan(
        outstandingShortfall: Double = 0,
        yesterdayStrain: Double = 0,
        napMinutes: Double = 0,
        nights: [SleepNightFeatures]? = nil,
        lastWake: Date? = nil,
        obligationWake: Date? = nil
    ) -> TonightPlan {
        let sleepNeed = need(
            outstandingShortfall: outstandingShortfall,
            yesterdayStrain: yesterdayStrain,
            napMinutes: napMinutes
        )
        let nights = nights ?? history()
        let wake = lastWake ?? (nights.first?.wakeTime ?? Date(timeIntervalSinceReferenceDate: 800_000_000))
        return TonightPlanner.build(
            nights: nights,
            sleepNeed: sleepNeed,
            outstandingShortfallMinutes: outstandingShortfall,
            lastWake: wake,
            now: Date(timeIntervalSinceReferenceDate: 800_000_000),
            obligationWake: obligationWake,
            obligationSource: obligationWake == nil ? .none : .bodyClock,
            calendar: calendar
        )
    }

    // MARK: - One repayment

    func testOutstandingShortfallIsRepaidOnceNotAsASliceOfASlice() {
        let outstanding = 180.0
        let tonight = plan(outstandingShortfall: outstanding)
        let expected = min(
            outstanding * SleepAutopilot.debtRepaymentRate,
            SleepAutopilot.maximumDebtRepayment
        )
        XCTAssertEqual(tonight.planning.tonightRepaymentMinutes, expected, accuracy: 0.001)
        XCTAssertEqual(
            tonight.autopilot?.debtRepaymentMinutes,
            expected,
            accuracy: 0.001
        )
        // The defect: handing Autopilot SleepNeed.debtMinutes (33% of 180)
        // would repay 25% of 59.4 ≈ 15, not 30.
        let slice = need(outstandingShortfall: outstanding).debtMinutes
        XCTAssertGreaterThan(expected, slice * SleepAutopilot.debtRepaymentRate + 1)
    }

    func testZeroSixtyAndOneEightyMinutesOfShortfall() {
        for shortfall in [0.0, 60, 180] {
            let tonight = plan(outstandingShortfall: shortfall)
            let expected = min(
                shortfall * SleepAutopilot.debtRepaymentRate,
                SleepAutopilot.maximumDebtRepayment
            )
            XCTAssertEqual(
                tonight.planning.tonightRepaymentMinutes,
                expected,
                accuracy: 0.001,
                "shortfall \(shortfall)"
            )
        }
    }

    func testStrainAndNapMoveTheTargetTheAutopilotSees() {
        let plain = plan()
        let strained = plan(yesterdayStrain: 18)
        let napped = plan(napMinutes: 40)
        XCTAssertGreaterThan(
            strained.planning.tonightNeedBeforeRepaymentMinutes,
            plain.planning.tonightNeedBeforeRepaymentMinutes
        )
        XCTAssertLessThan(
            napped.planning.tonightNeedBeforeRepaymentMinutes,
            plain.planning.tonightNeedBeforeRepaymentMinutes
        )
    }

    // MARK: - One bedtime

    func testEveryConsumerReadsTheSameBedtime() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let tonight = plan(outstandingShortfall: 120)
        let bed = tonight.bedtime(now: now, calendar: calendar)
        XCTAssertNotNil(bed)

        // Autopilot, resolved the same way Today/Watch/reminders resolve it.
        let fromAutopilot = tonight.autopilot.flatMap {
            PlannedBedtimeResolver.nextOccurrence(
                ofMinutesFromMidnight: $0.targetBedtimeMinutes,
                after: now,
                calendar: calendar
            )
        }
        XCTAssertEqual(bed, fromAutopilot)

        // Tomorrow with no calendar event uses the same Autopilot wiring.
        let tomorrow = ZoonTomorrow.plan(
            now: now,
            event: nil,
            nights: history(),
            planning: tonight.planning,
            calendar: calendar
        )
        XCTAssertEqual(tomorrow?.bedtime, bed)

        // Nap Coach is handed that same instant, not a second calculation.
        let nap = NapCoach.recommend(
            now: now,
            debtMinutes: 120,
            plannedBedtime: bed,
            napMinutesToday: 0
        )
        _ = nap
        XCTAssertEqual(bed, tonight.bedtime(now: now, calendar: calendar))
    }

    func testWhatIfBaselineMatchesTonightsNeed() {
        let tonight = plan(outstandingShortfall: 120)
        XCTAssertEqual(
            tonight.suggestedSleepTargetMinutes,
            tonight.planning.tonightNeedMinutes,
            accuracy: 0.001
        )
        XCTAssertEqual(
            tonight.suggestedSleepTargetMinutes,
            tonight.planning.tonightNeedBeforeRepaymentMinutes
                + tonight.planning.tonightRepaymentMinutes,
            accuracy: 0.001
        )
    }

    func testRunwayFirstNightMatchesTonightsNeedWhenThereIsNoCalendarEvent() throws {
        let tonight = plan(outstandingShortfall: 120)
        let runway = try XCTUnwrap(
            SleepRunway.build(
                nights: history(),
                planning: tonight.planning,
                calendar: calendar
            )
        )
        let first = try XCTUnwrap(runway.days.first)
        XCTAssertEqual(first.needMinutes, tonight.planning.tonightNeedMinutes, accuracy: 1)
    }

    /// Too little history: Autopilot is silent, fallback subtracts the
    /// planning target, not the composed SleepNeed total.
    func testFallbackWithoutAHabitUsesThePlanningTargetNotTheComposedTotal() {
        let outstanding: Double = 180
        let sleepNeed = need(outstandingShortfall: outstanding)
        let lastWake = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let tonight = TonightPlanner.build(
            nights: [],
            sleepNeed: sleepNeed,
            outstandingShortfallMinutes: outstanding,
            lastWake: lastWake,
            now: lastWake,
            calendar: calendar
        )
        XCTAssertNil(tonight.autopilot)
        XCTAssertEqual(tonight.suggestedSleepTargetMinutes, tonight.planning.tonightNeedMinutes, accuracy: 0.001)
        XCTAssertNotEqual(tonight.suggestedSleepTargetMinutes, sleepNeed.totalNeedMinutes, accuracy: 1)

        let bed = tonight.bedtime(now: lastWake, calendar: calendar)
        let naiveComposed = calendar.date(
            byAdding: .day, value: 1, to: lastWake
        ).flatMap {
            calendar.date(
                bySettingHour: calendar.component(.hour, from: lastWake),
                minute: calendar.component(.minute, from: lastWake),
                second: 0,
                of: $0
            )
        }.map { $0.addingTimeInterval(-sleepNeed.totalNeedMinutes * 60) }
        XCTAssertNotEqual(
            bed?.timeIntervalSince1970,
            naiveComposed?.timeIntervalSince1970,
            accuracy: 30,
            "fallback must not still be wake-minus-composed-need"
        )
    }

    func testSleepNeedSummaryDoesNotClaimAMeasurement() {
        let sleepNeed = need(outstandingShortfall: 0)
        XCTAssertFalse(sleepNeed.summary.contains("You needed"))
        XCTAssertTrue(sleepNeed.summary.lowercased().contains("target"))
        XCTAssertEqual(
            sleepNeed.contributions.first { $0.kind == .debt }?.label,
            nil
        )
        let withShortfall = need(outstandingShortfall: 180)
        XCTAssertEqual(
            withShortfall.contributions.first { $0.kind == .debt }?.label,
            "Shortfall repayment"
        )
    }

    func testTomorrowAndRunwayShareTonightsPlanningInputs() throws {
        let tonight = plan(outstandingShortfall: 120)
        let tomorrow = ZoonTomorrow.plan(
            now: Date(timeIntervalSinceReferenceDate: 800_000_000),
            event: nil,
            nights: history(),
            planning: tonight.planning,
            calendar: calendar
        )
        XCTAssertEqual(tomorrow?.targetSleepMinutes ?? 0, tonight.planning.tonightNeedMinutes, accuracy: 1)
        let runway = try XCTUnwrap(
            SleepRunway.build(
                nights: history(),
                planning: tonight.planning,
                calendar: calendar
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(runway.days.first).needMinutes,
            tonight.planning.tonightNeedMinutes,
            accuracy: 1
        )
    }
}

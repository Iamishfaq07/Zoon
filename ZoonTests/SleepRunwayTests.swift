import XCTest

/// Covers the seven-day horizon.
///
/// The question it exists to answer is not "how will I sleep on Thursday" —
/// nothing here predicts that — but "where does the schedule stop leaving
/// room for the sleep I need, while there is still time to move something".
/// Somebody with a 06:00 start on Thursday cannot fix Thursday on Wednesday
/// night. They can move Tuesday.
final class SleepRunwayTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)
        )!
    }

    /// Monday evening. The horizon therefore starts on Tuesday the 15th.
    private var now: Date { date(14, 21) }

    /// A fortnight of identical nights: bed at 23:00, wake at 07:00.
    private func history(
        bedtimeHour: Int = 23,
        inBedMinutes: Double = 480,
        nights: Int = 14
    ) -> [SleepNightFeatures] {
        (1...nights).map { index in
            Fixture.night(
                timeAsleepMinutes: inBedMinutes - 30,
                timeInBedMinutes: inBedMinutes,
                bedtimeHour: bedtimeHour,
                wakeDay: calendar.date(byAdding: .day, value: -index, to: date(14, 12))!
            )
        }
    }

    private func build(
        nights: [SleepNightFeatures]? = nil,
        need: Double = 465,
        debt: Double = 0,
        commitments: [Date: Date] = [:],
        manual: ManualCommitment? = nil,
        obligationWeekdays: Set<Int> = [],
        readyBuffer: Double = 50
    ) -> SleepRunway.Plan? {
        SleepRunway.build(
            now: now,
            nights: nights ?? history(),
            sleepNeedMinutes: need,
            sleepDebtMinutes: debt,
            commitments: commitments,
            manual: manual,
            obligationWeekdays: obligationWeekdays,
            readyBufferMinutes: readyBuffer,
            calendar: calendar
        )
    }

    // MARK: - Shape

    func testTheHorizonStartsTomorrowAndRunsSevenMornings() throws {
        let plan = try XCTUnwrap(build())
        XCTAssertEqual(plan.days.count, SleepRunway.horizonDays)
        XCTAssertEqual(calendar.startOfDay(for: plan.days[0].date), date(15, 0))
        XCTAssertEqual(calendar.startOfDay(for: plan.days[6].date), date(21, 0))
    }

    /// A runway drawn from a habit nobody has yet is a runway drawn from
    /// nothing.
    func testTooLittleHistoryProducesNoRunway() {
        XCTAssertNil(build(nights: history(nights: 4)))
    }

    func testNoSleepNeedProducesNoRunway() {
        XCTAssertNil(build(need: 0))
    }

    // MARK: - Opportunity from habit

    /// Bed at 23:00, wake at 07:00, no commitments: eight hours every
    /// morning, and a need of 7h45 fits.
    func testAHabitualWeekLeavesRoomForTheNeed() throws {
        let plan = try XCTUnwrap(build())
        for day in plan.days {
            XCTAssertEqual(day.opportunityMinutes, 480, accuracy: 1, "\(day.date)")
            XCTAssertFalse(day.isShort)
        }
        XCTAssertNil(plan.firstShortDay)
        XCTAssertTrue(plan.sentence.contains("leaves room"), plan.sentence)
    }

    /// The bedtime belongs to the evening *before* the morning it is paired
    /// with. Getting this backwards is how an eight-hour window becomes a
    /// minus-sixteen-hour one.
    func testTheBedtimeSitsOnTheEveningBeforeItsMorning() throws {
        let plan = try XCTUnwrap(build())
        let tuesday = plan.days[0]
        XCTAssertEqual(tuesday.bedtime, date(14, 23))
        XCTAssertEqual(tuesday.wake, date(15, 7))
    }

    // MARK: - Commitments

    /// The case the feature exists for: a 06:00 start on Thursday, two days
    /// out, while there is still a Tuesday and a Wednesday to move.
    func testAnEarlyCommitmentOpensAGapAndIsNamed() throws {
        let plan = try XCTUnwrap(build(
            commitments: [date(17, 0): date(17, 6, 30)]
        ))
        let thursday = try XCTUnwrap(plan.days.first { calendar.component(.day, from: $0.date) == 17 })

        // 06:30 start, fifty minutes to get ready, so wake at 05:40 — and a
        // 23:00 bedtime leaves 6h40.
        XCTAssertEqual(thursday.wake, date(17, 5, 40))
        XCTAssertEqual(thursday.opportunityMinutes, 400, accuracy: 1)
        XCTAssertTrue(thursday.isShort)
        XCTAssertEqual(thursday.wakeSource, .calendar)
        XCTAssertEqual(plan.firstShortDay?.date, thursday.date)
        XCTAssertTrue(plan.sentence.contains("Thursday"), plan.sentence)
        XCTAssertTrue(plan.sentence.contains("fixed"), plan.sentence)
        XCTAssertTrue(plan.usedCalendar)
    }

    /// An afternoon meeting is not a morning start and must not move wake.
    func testALateCommitmentIsIgnored() throws {
        let plan = try XCTUnwrap(build(
            commitments: [date(17, 0): date(17, 15, 0)]
        ))
        let thursday = try XCTUnwrap(plan.days.first { calendar.component(.day, from: $0.date) == 17 })
        XCTAssertEqual(thursday.wake, date(17, 7))
        XCTAssertFalse(plan.usedCalendar)
    }

    /// The ready buffer is the person's, and it moves the whole horizon.
    func testTheReadyBufferMovesTheWakeTime() throws {
        let plan = try XCTUnwrap(build(
            commitments: [date(17, 0): date(17, 6, 30)],
            readyBuffer: 20
        ))
        let thursday = try XCTUnwrap(plan.days.first { calendar.component(.day, from: $0.date) == 17 })
        XCTAssertEqual(thursday.wake, date(17, 6, 10))
    }

    // MARK: - The standing manual time

    /// A 07:00 alarm someone keeps for work is not a claim about their
    /// Sunday, so it applies to obligation days only.
    func testAManualTimeAppliesOnlyToObligationDays() throws {
        // Weekdays: Monday(2) through Friday(6) in Gregorian numbering.
        let plan = try XCTUnwrap(build(
            manual: ManualCommitment(hour: 6, minute: 0),
            obligationWeekdays: [2, 3, 4, 5, 6]
        ))
        let friday = try XCTUnwrap(plan.days.first { calendar.component(.day, from: $0.date) == 18 })
        let saturday = try XCTUnwrap(plan.days.first { calendar.component(.day, from: $0.date) == 19 })

        XCTAssertEqual(friday.wakeSource, .manual)
        XCTAssertEqual(friday.wake, date(18, 6))
        XCTAssertNotEqual(saturday.wakeSource, .manual)
        XCTAssertEqual(saturday.wake, date(19, 7))
    }

    /// A dated commitment beats a standing intent on the day it falls.
    func testACalendarCommitmentOutranksTheManualTime() throws {
        let plan = try XCTUnwrap(build(
            commitments: [date(17, 0): date(17, 6, 30)],
            manual: ManualCommitment(hour: 8, minute: 0),
            obligationWeekdays: []
        ))
        let thursday = try XCTUnwrap(plan.days.first { calendar.component(.day, from: $0.date) == 17 })
        XCTAssertEqual(thursday.wakeSource, .calendar)
    }

    // MARK: - Shortfall carried forward

    /// Outstanding shortfall raises the need, using the same capped
    /// repayment rule the single-night planner applies rather than a second
    /// one invented for the horizon.
    func testOutstandingShortfallRaisesTheFirstNightsNeed() throws {
        let plain = try XCTUnwrap(build())
        let indebted = try XCTUnwrap(build(debt: 200))
        XCTAssertGreaterThan(indebted.days[0].needMinutes, plain.days[0].needMinutes)
        XCTAssertLessThanOrEqual(
            indebted.days[0].needMinutes - plain.days[0].needMinutes,
            SleepAutopilot.maximumDebtRepayment
        )
    }

    /// A week of windows that fit pays the shortfall down rather than
    /// carrying it forever.
    func testAWeekOfAdequateWindowsClearsTheShortfall() throws {
        let plan = try XCTUnwrap(build(debt: 120))
        XCTAssertLessThan(
            try XCTUnwrap(plan.days.last).projectedShortfallMinutes,
            plan.days[0].projectedShortfallMinutes
        )
    }

    /// Short windows accumulate. That accumulation is the whole argument for
    /// looking a week ahead rather than a night.
    func testRepeatedShortWindowsAccumulate() throws {
        // Bed at 01:00, wake at 07:00: a six-hour habit against a 7h45 need.
        let plan = try XCTUnwrap(build(nights: history(bedtimeHour: 1, inBedMinutes: 360)))
        XCTAssertGreaterThan(
            try XCTUnwrap(plan.days.last).projectedShortfallMinutes,
            plan.days[0].projectedShortfallMinutes
        )
        XCTAssertTrue(plan.days[0].isShort)
    }

    // MARK: - What it refuses to say

    /// Opportunity is a ceiling, not a forecast, and the caveat has to say
    /// so. Nothing here may predict recovery or a score.
    func testTheCaveatSaysOpportunityIsNotAPrediction() throws {
        let plan = try XCTUnwrap(build())
        XCTAssertTrue(plan.caveat.lowercased().contains("not a prediction"), plan.caveat)
        for text in plan.days.map({ "\($0)" }) + [plan.sentence, plan.caveat] {
            XCTAssertFalse(text.lowercased().contains("you will feel"), text)
        }
    }

    /// Confidence follows the history behind the habit, and a horizon with
    /// no calendar behind it cannot be its most confident.
    func testConfidenceReflectsHistoryAndCalendar() throws {
        XCTAssertEqual(try XCTUnwrap(build(nights: history(nights: 8))).confidence, .low)
        XCTAssertEqual(try XCTUnwrap(build(nights: history(nights: 16))).confidence, .moderate)
        XCTAssertEqual(try XCTUnwrap(build(nights: history(nights: 24))).confidence, .moderate)
        XCTAssertEqual(
            try XCTUnwrap(build(
                nights: history(nights: 24),
                commitments: [date(17, 0): date(17, 9, 0)]
            )).confidence,
            .high
        )
    }
}

import XCTest

/// §16. The optimizer allocates against a number the runway already produced,
/// so the arithmetic is small and the constraints are the whole feature: a
/// rate limit it may not exceed, a wake time it may not move, a shift it may
/// not plan inside, and a residual it may not hide.
final class SleepRunwayOptimizerTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var monday: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 14
        return calendar.date(from: components)!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday)!
    }

    private func runwayDay(
        _ offset: Int,
        opportunityMinutes: Double,
        wakeSource: SleepRunway.WakeSource = .habit
    ) -> SleepRunway.Day {
        let wake = day(offset).addingTimeInterval(7 * 3600)
        return SleepRunway.Day(
            date: day(offset),
            needMinutes: 480,
            opportunityMinutes: opportunityMinutes,
            bedtime: wake.addingTimeInterval(-opportunityMinutes * 60),
            wake: wake,
            wakeSource: wakeSource,
            projectedShortfallMinutes: 0
        )
    }

    private func plan(_ days: [SleepRunway.Day]) -> SleepRunway.Plan {
        SleepRunway.Plan(
            days: days,
            firstShortDay: days.first(where: \.isShort),
            sentence: "", caveat: "", confidence: .moderate, usedCalendar: false
        )
    }

    /// A week where `shortOffset` is `gap` minutes short and every other night
    /// has `slack` minutes of room.
    private func week(
        shortOffset: Int = 4,
        gap: Double = 55,
        slack: Double = 60,
        constrainedWakeSource: SleepRunway.WakeSource = .habit
    ) -> SleepRunway.Plan {
        plan((0..<7).map { offset in
            offset == shortOffset
                ? runwayDay(offset, opportunityMinutes: 480 - gap, wakeSource: constrainedWakeSource)
                : runwayDay(offset, opportunityMinutes: 480 + slack)
        })
    }

    // MARK: - Allocating against the gap

    /// The brief's own example, with the rate limit applied: a fifty-five
    /// minute gap, found across the nights before it, twenty at a time.
    func testTheGapIsAllocatedNearestTheConstraintFirst() throws {
        let optimized = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(runway: week(), calendar: calendar)
        )
        let shifts = optimized.steps.compactMap { step -> (Date, Double)? in
            guard case let .shiftBedtime(date, minutes, _) = step else { return nil }
            return (date, minutes)
        }
        XCTAssertEqual(shifts.map(\.0), [day(1), day(2), day(3)])
        // Nearest first: Thursday takes 20, Wednesday 20, Tuesday the last 15.
        XCTAssertEqual(shifts.map(\.1), [15, 20, 20])
        XCTAssertEqual(optimized.allocatedMinutes, 55, accuracy: 0.001)
        XCTAssertTrue(optimized.closesTheGap)
    }

    /// Smallest feasible means smallest. A fifteen-minute gap is one night's
    /// fifteen minutes, not three nights of five.
    func testASmallGapIsOneNightsAdjustment() throws {
        let optimized = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(runway: week(gap: 15), calendar: calendar)
        )
        XCTAssertEqual(optimized.steps.filter { $0.minutes > 0 }.count, 1)
        XCTAssertEqual(optimized.allocatedMinutes, 15, accuracy: 0.001)
    }

    // MARK: - The rate limit

    func testNoNightMovesMoreThanTheAutopilotWould() throws {
        let optimized = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(
                runway: week(gap: 200, slack: 240), calendar: calendar
            )
        )
        for step in optimized.steps {
            XCTAssertLessThanOrEqual(step.minutes, SleepAutopilot.maximumNightlyShift)
        }
    }

    func testTheRateLimitIsReadFromTheAutopilotRatherThanCopied() {
        XCTAssertEqual(
            SleepRunwayOptimizer.maximumNightlyShiftMinutes,
            SleepAutopilot.maximumNightlyShift
        )
    }

    // MARK: - What it cannot reach

    /// Three nights at twenty minutes is sixty. A ninety-minute gap cannot be
    /// closed, and the plan says so rather than stopping quietly at sixty and
    /// reading as though it worked.
    func testAGapTooLargeToCloseStatesWhatIsLeft() throws {
        let optimized = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(runway: week(gap: 90, slack: 120), calendar: calendar)
        )
        XCTAssertEqual(optimized.allocatedMinutes, 60, accuracy: 0.001)
        XCTAssertEqual(optimized.residualGapMinutes, 30, accuracy: 0.001)
        XCTAssertFalse(optimized.closesTheGap)
        XCTAssertTrue(optimized.sentence.contains("30"), optimized.sentence)
        XCTAssertTrue(optimized.sentence.contains("cannot find"), optimized.sentence)
    }

    /// A night with no room of its own contributes nothing. Taking from it
    /// would move the shortfall rather than close it.
    func testNoRoomAnywhereProducesNoPlanRatherThanAnEmptyOne() {
        let days = (0..<7).map { runwayDay($0, opportunityMinutes: $0 == 4 ? 425 : 480) }
        XCTAssertNil(SleepRunwayOptimizer.optimize(runway: plan(days), calendar: calendar))
    }

    func testAWeekWithNoGapProducesNothing() {
        let days = (0..<7).map { runwayDay($0, opportunityMinutes: 540) }
        XCTAssertNil(SleepRunwayOptimizer.optimize(runway: plan(days), calendar: calendar))
    }

    /// A constraint on the first morning of the horizon has no earlier night
    /// to draw on. That is tonight, and Zoon Tomorrow owns it.
    func testAConstraintOnTheFirstMorningHasNothingBeforeIt() {
        XCTAssertNil(SleepRunwayOptimizer.optimize(runway: week(shortOffset: 0), calendar: calendar))
    }

    // MARK: - Wake times and shifts

    /// The plan moves bedtimes. It never proposes getting up later, because
    /// the wake time is usually the part that cannot move -- and where it is
    /// pinned by a commitment, protecting it is a step of its own.
    func testTheConstrainedMorningsFixedWakeTimeIsProtectedNotMoved() throws {
        let optimized = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(
                runway: week(constrainedWakeSource: .calendar), calendar: calendar
            )
        )
        let protects = optimized.steps.filter {
            if case .protectWakeTime = $0 { return true }
            return false
        }
        XCTAssertEqual(protects.count, 1)
        XCTAssertEqual(protects.first?.date, day(4))
    }

    func testAHabitualWakeTimeNeedsNoProtecting() throws {
        let optimized = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(runway: week(), calendar: calendar)
        )
        XCTAssertFalse(optimized.steps.contains {
            if case .protectWakeTime = $0 { return true }
            return false
        })
    }

    /// Every step is a bedtime moved *earlier*, on a night before the
    /// constraint. Nothing here ever asks for a later wake.
    func testEveryAdjustmentIsABedtimeMovedEarlier() throws {
        let optimized = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(runway: week(), calendar: calendar)
        )
        for step in optimized.steps {
            guard case let .shiftBedtime(date, minutes, _) = step else { continue }
            XCTAssertGreaterThan(minutes, 0)
            XCTAssertLessThan(date, optimized.constrainedDate)
        }
    }

    func testANightInsideAShiftIsNotPlannedInto() throws {
        let plain = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(runway: week(), calendar: calendar)
        )
        XCTAssertTrue(plain.steps.contains { $0.date == day(3) })

        let shift = ShiftRoster.Occurrence(
            shiftID: UUID(),
            start: day(2).addingTimeInterval(21 * 3600),
            end: day(3).addingTimeInterval(5 * 3600),
            label: "Nights"
        )
        let withShift = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(
                runway: week(), shiftOccurrences: [shift], calendar: calendar
            )
        )
        XCTAssertFalse(withShift.steps.contains { $0.date == day(3) })
    }

    // MARK: - A planner, not a predictor

    func testNothingPredictsHowTheNightsWillGo() throws {
        let optimized = try XCTUnwrap(
            SleepRunwayOptimizer.optimize(runway: week(), calendar: calendar)
        )
        for line in [optimized.sentence, optimized.caveat] {
            for banned in ["you will feel", "recovery will", "you'll be", "guarantees",
                           "will restore", "readiness will"] {
                XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
            }
            XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(line), line)
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(line), line)
        }
        XCTAssertTrue(optimized.caveat.contains("sleep opportunity"), optimized.caveat)
        XCTAssertTrue(optimized.caveat.contains("does not predict"), optimized.caveat)
    }
}

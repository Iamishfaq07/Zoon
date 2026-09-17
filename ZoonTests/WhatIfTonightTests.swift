import XCTest

/// Covers the interactive Tonight window.
///
/// Everything here is arithmetic on a clock, and the tests exist as much to
/// pin what it refuses to say as what it says: no Recovery number, no Sleep
/// Score, no claim about how the night will go.
final class WhatIfTonightTests: XCTestCase {

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

    /// The brief's example: an 11:15 plan against a 7:00 alarm.
    private func model(
        bedtime: Date,
        wake: Date = Date(timeIntervalSince1970: 0),
        need: Double = 465,
        shortfall: Double = 0,
        reference: Bool = true
    ) -> WhatIfTonight {
        let resolvedWake = wake == Date(timeIntervalSince1970: 0) ? date(15, 7) : wake
        return WhatIfTonight(
            bedtime: bedtime,
            wake: resolvedWake,
            needMinutes: need,
            shortfallMinutes: shortfall,
            reference: reference
                ? WhatIfTonight.Reference(bedtime: date(14, 23, 15), wake: date(15, 7))
                : nil
        )
    }

    // MARK: - The subtraction

    func testMovingBedtimeLaterCostsTheWindowExactlyThatMuch() {
        let planned = model(bedtime: date(14, 23, 15))
        let later = model(bedtime: date(15, 0, 10))
        XCTAssertEqual(planned.opportunityMinutes, 465, accuracy: 0.001)
        XCTAssertEqual(later.opportunityMinutes, 410, accuracy: 0.001)
        XCTAssertEqual(planned.opportunityMinutes - later.opportunityMinutes, 55, accuracy: 0.001)
    }

    /// The brief's sentence, near enough: "your maximum sleep opportunity
    /// before a 7:00 wake time falls to 6h 50m".
    func testTheComparativeSentenceNamesBothTimesAndTheDirection() {
        let sentence = model(bedtime: date(15, 0, 10)).sentence(calendar: calendar)
        XCTAssertTrue(sentence.contains("instead of"), sentence)
        XCTAssertTrue(sentence.contains("falls to"), sentence)
        XCTAssertTrue(sentence.contains("6h 50m") || sentence.contains("6h50m"), sentence)
    }

    func testAnEarlierBedtimeRises() {
        let sentence = model(bedtime: date(14, 22, 15)).sentence(calendar: calendar)
        XCTAssertTrue(sentence.contains("rises to"), sentence)
    }

    /// Moving the alarm rather than the bedtime has to say so, or the
    /// sentence describes a change the person did not make.
    func testMovingTheWakeTimeIsDescribedAsMovingTheWakeTime() {
        let sentence = model(bedtime: date(14, 23, 15), wake: date(15, 6, 0))
            .sentence(calendar: calendar)
        XCTAssertTrue(sentence.contains("If you wake at"), sentence)
    }

    /// An untouched window has nothing to compare against, so it states
    /// rather than compares.
    func testAnUnmovedWindowIsNotDescribedAsAChange() {
        let sentence = model(bedtime: date(14, 23, 15)).sentence(calendar: calendar)
        XCTAssertFalse(sentence.contains("instead of"), sentence)
        XCTAssertTrue(sentence.contains("enough for what you need"), sentence)
    }

    /// A five-minute nudge is inside the resolution the need is good to.
    func testATinyAdjustmentIsNotWorthAComparison() {
        let sentence = model(bedtime: date(14, 23, 17)).sentence(calendar: calendar)
        XCTAssertFalse(sentence.contains("instead of"), sentence)
    }

    // MARK: - Against the need

    func testAShortWindowNamesTheGap() {
        let short = model(bedtime: date(15, 0, 30))
        XCTAssertTrue(short.isShort)
        XCTAssertEqual(short.gapMinutes, 75, accuracy: 0.001)
        let rows = short.rows(now: date(14, 20), calendar: calendar)
        let against = rows.first { $0.label == "Against your need" }
        XCTAssertEqual(against?.value.hasPrefix("−"), true, "\(String(describing: against))")
    }

    func testAWindowThatCoversTheNeedSaysSo() {
        let rows = model(bedtime: date(14, 22, 30)).rows(now: date(14, 20), calendar: calendar)
        XCTAssertEqual(rows.first { $0.label == "Against your need" }?.value, "covered")
    }

    // MARK: - Shortfall

    /// The optimistic bound, and only that: a window that cannot repay
    /// anything even in principle is the finding worth surfacing.
    func testAGenerousWindowProjectsTheShortfallDown() {
        let model = model(bedtime: date(14, 21, 30), shortfall: 120)
        XCTAssertLessThan(model.projectedShortfallMinutes, 120)
    }

    func testAShortWindowProjectsTheShortfallUp() {
        let model = model(bedtime: date(15, 0, 30), shortfall: 120)
        XCTAssertGreaterThan(model.projectedShortfallMinutes, 120)
    }

    func testTheProjectedShortfallNeverGoesNegative() {
        let model = model(bedtime: date(14, 18, 0), shortfall: 0)
        XCTAssertEqual(model.projectedShortfallMinutes, 0)
    }

    // MARK: - The offsets that follow from the window

    func testWindDownLeadsTheBedtime() {
        let model = model(bedtime: date(14, 23, 15))
        XCTAssertEqual(
            model.windDown,
            date(14, 23, 15).addingTimeInterval(-ZoonTomorrow.windDownLeadMinutes * 60)
        )
    }

    func testMorningLightFollowsTheWake() {
        let model = model(bedtime: date(14, 23, 15))
        XCTAssertEqual(
            model.morningLightUntil,
            date(15, 7).addingTimeInterval(ZoonTomorrow.morningLightMinutes * 60)
        )
    }

    /// The caffeine cutoff moves with the window, and is the general
    /// eight-hour guideline rather than a personal sensitivity.
    func testTheCaffeineCutoffMovesWithTheBedtime() throws {
        let early = try XCTUnwrap(model(bedtime: date(14, 22, 0)).caffeineCutoff(now: date(14, 12)))
        let late = try XCTUnwrap(model(bedtime: date(15, 0, 0)).caffeineCutoff(now: date(14, 12)))
        XCTAssertEqual(late.timeIntervalSince(early), 2 * 3600, accuracy: 1)
    }

    /// An inverted window is a person's mistake, not a crash and not a
    /// negative duration.
    func testAWakeBeforeBedtimeIsZeroNotNegative() {
        let inverted = model(bedtime: date(15, 8, 0), wake: date(15, 7, 0))
        XCTAssertEqual(inverted.opportunityMinutes, 0)
        XCTAssertTrue(inverted.isShort)
    }

    // MARK: - What it must never say

    func testNothingHerePredictsRecoveryOrAScore() {
        let model = model(bedtime: date(15, 0, 10), shortfall: 90)
        var text = model.sentence(calendar: calendar)
        for row in model.rows(now: date(14, 20), calendar: calendar) {
            text += " \(row.label) \(row.value)"
        }
        for forbidden in ["recovery", "score", "you will feel", "readiness"] {
            XCTAssertFalse(text.lowercased().contains(forbidden), "\(forbidden) in: \(text)")
        }
    }
}

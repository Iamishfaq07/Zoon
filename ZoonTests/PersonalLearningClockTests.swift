import XCTest

/// §7. `PersonalLearning` carried two hand-rolled copies of "clock time", both
/// of which cut the day at noon and added twenty-four hours to anything below
/// the cut.
///
/// That rule is not wrong so much as it is a rule about one kind of sleeper.
/// It works for somebody who goes to bed between 21:00 and 02:00, because the
/// cut falls in the middle of their waking day where no bedtime ever lands.
/// Move the sleeper and the cut lands in the middle of their *sleep*: a nurse
/// coming off nights goes to bed at 11:50 one day and 12:10 the next, twenty
/// minutes apart, and the noon cut reported them as twenty-three hours and
/// forty minutes apart — comfortably past the sixty-minute threshold that
/// announces "your timing shifted".
///
/// Every seam is tested here rather than only the midnight one, because the
/// midnight seam is the one the old code got right.
final class PersonalLearningClockTests: XCTestCase {

    /// Not actionable, so the timing item is the one under test rather than
    /// being crowded out by body signals.
    private let quietRadar = HealthRadar(signals: [], nightCount: 0)

    /// Ten nights: the three most recent at `recent`, the seven before them at
    /// `earlier` — the exact windows `proactiveItems` slices.
    private func nights(
        recent: (hour: Int, minute: Int),
        earlier: (hour: Int, minute: Int),
        recentZone: String = "UTC",
        earlierZone: String = "UTC"
    ) -> [SleepNightFeatures] {
        (1...10).map { daysAgo in
            let isRecent = daysAgo <= 3
            let time = isRecent ? recent : earlier
            return Fixture.night(
                daysAgo: daysAgo,
                bedtimeHour: time.hour,
                bedtimeMinuteOffset: time.minute,
                timeZoneIdentifier: isRecent ? recentZone : earlierZone
            )
        }
    }

    private func timingItem(
        recent: (hour: Int, minute: Int),
        earlier: (hour: Int, minute: Int),
        recentZone: String = "UTC",
        earlierZone: String = "UTC"
    ) -> PersonalLearning.ProactiveItem? {
        PersonalLearning.proactiveItems(
            nights: nights(recent: recent, earlier: earlier,
                           recentZone: recentZone, earlierZone: earlierZone),
            radar: quietRadar
        ).first { $0.kind == .timing }
    }

    // MARK: - The seams

    /// The one the old code handled. Kept so the consolidation is shown not to
    /// have cost anything.
    func testTwentyMinutesAcrossMidnightIsNotAShift() {
        XCTAssertNil(timingItem(recent: (0, 10), earlier: (23, 50)))
    }

    /// The one the old code broke. A day sleeper's twenty minutes became
    /// twenty-three hours and forty.
    func testTwentyMinutesAcrossNoonIsNotAShift() {
        XCTAssertNil(timingItem(recent: (12, 10), earlier: (11, 50)))
    }

    /// Nothing special happens at nine in the morning, and nothing should.
    func testTwentyMinutesAcrossNineInTheMorningIsNotAShift() {
        XCTAssertNil(timingItem(recent: (9, 10), earlier: (8, 50)))
    }

    /// 18:00 is where `circularMinutesFromMidnight` folds. The engine uses the
    /// unfolded `clockMinutes` precisely so that seam is not a seam either.
    func testTwentyMinutesAcrossSixInTheEveningIsNotAShift() {
        XCTAssertNil(timingItem(recent: (18, 10), earlier: (17, 50)))
    }

    /// A rotating roster crosses every seam there is. None of the crossings is
    /// a shift in timing; the person's bedtime is where it always was.
    func testARotatingRosterDoesNotReadAsDriftEverySeamItCrosses() {
        for hour in 0...23 {
            let before = (hour: hour, minute: 50)
            let after = (hour: (hour + 1) % 24, minute: 10)
            XCTAssertNil(
                timingItem(recent: after, earlier: before),
                "a twenty-minute move at \(hour):50 read as a timing shift"
            )
        }
    }

    // MARK: - A real shift, and which way it went

    func testALaterBedtimeIsReportedAsLaterWithItsSize() throws {
        let item = try XCTUnwrap(timingItem(recent: (1, 0), earlier: (23, 0)))
        XCTAssertTrue(item.detail.contains("120"), item.detail)
        XCTAssertTrue(item.detail.contains("later"), item.detail)
    }

    func testAnEarlierBedtimeIsReportedAsEarlier() throws {
        let item = try XCTUnwrap(timingItem(recent: (21, 0), earlier: (23, 0)))
        XCTAssertTrue(item.detail.contains("120"), item.detail)
        XCTAssertTrue(item.detail.contains("earlier"), item.detail)
    }

    /// The threshold is an hour, and it is a circular hour: fifty-nine minutes
    /// is not a shift whichever side of midnight it is measured from.
    func testJustUnderTheThresholdIsStillNotAShift() {
        XCTAssertNil(timingItem(recent: (0, 29), earlier: (23, 30)))
    }

    // MARK: - Historical records belong to their historical timezone

    /// Someone who went to bed at 23:00 every night, then flew five time zones
    /// west and went to bed at 23:00 there, has not changed their habit in any
    /// sense the copy means. Reading the older nights in the device's current
    /// zone re-dated all seven of them and announced a five-hour shift nobody
    /// made.
    func testFlyingDoesNotInventATimingShift() {
        XCTAssertNil(
            timingItem(
                recent: (23, 0), earlier: (23, 0),
                recentZone: "America/New_York", earlierZone: "Europe/London"
            )
        )
    }

    // MARK: - Resilience reads the same clock

    /// The other copy of the noon cut lived in `resilience`, where it set the
    /// centre that recovery nights are matched back to. For a day sleeper the
    /// centre landed in the middle of their waking day, so no night ever came
    /// back inside range and the feature silently produced nothing.
    func testADaySleeperRecoversTheirTimingLikeAnybodyElse() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Bedtimes straddling noon — 11:40 and 12:10 — for twenty nights.
        // Both are anchored off the same hour so every night still files under
        // its own day; only the minutes cross the old cut.
        let nights = (1...20).map { daysAgo -> SleepNightFeatures in
            Fixture.night(
                daysAgo: daysAgo,
                bedtimeHour: 12,
                bedtimeMinuteOffset: daysAgo.isMultiple(of: 2) ? -20 : 10,
                timeZoneIdentifier: "UTC"
            )
        }
        let ordered = nights.sorted { $0.date < $1.date }
        // Two separate disruptions, each far enough from the ends to leave a
        // five-night baseline behind it and recovery nights ahead of it.
        let disruptions = Set([ordered[7].date, ordered[13].date])

        let found = PersonalLearning.resilience(
            nights: nights, disruptionDates: disruptions, calendar: calendar
        )
        XCTAssertTrue(
            found.contains { $0.metric == .sleepTiming },
            "a day sleeper's timing never came back inside their own range"
        )
    }
}

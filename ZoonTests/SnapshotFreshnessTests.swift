import XCTest

/// Whether the numbers on the watch are about last night, or about a night
/// that has since been replaced.
///
/// The failure this names: the watch has no pipeline of its own, so if the
/// phone app has not been opened it keeps rendering the last snapshot it
/// received -- and renders it exactly as confidently as a fresh one.
final class SnapshotFreshnessTests: XCTestCase {

    private let calendar = Calendar.current

    /// `SleepSnapshot.date` is derived from the night it was built from, so
    /// the night is what has to move.
    private func snapshot(nightsAgo: Int) -> SleepSnapshot {
        SleepSnapshot(
            features: Fixture.night(daysAgo: nightsAgo),
            score: SleepScore(value: 80, components: []),
            insight: SleepInsight(
                summary: "summary",
                likelyCause: "cause",
                actionableTip: "tip",
                confidence: .medium
            ),
            goalMinutes: 480
        )
    }

    /// Today at `hour`. `XCTUnwrap` rather than `!` because setting an hour
    /// can legitimately fail on a DST transition day, and a test that
    /// crashes twice a year is worse than one that fails loudly.
    private func today(at hour: Int) throws -> Date {
        try XCTUnwrap(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()))
    }

    private func state(nightsAgo: Int, at hour: Int) throws -> SnapshotFreshness.State {
        SnapshotFreshness.state(
            of: snapshot(nightsAgo: nightsAgo),
            now: try today(at: hour),
            calendar: calendar
        )
    }

    // MARK: - Current

    func testTonightsOwnNightIsCurrent() throws {
        XCTAssertEqual(try state(nightsAgo: 0, at: 8), .current)
        XCTAssertEqual(try state(nightsAgo: 0, at: 22), .current)
    }

    /// A warning that fires every single morning is a warning nobody reads.
    /// Before the settled hour, a snapshot still describing yesterday is not
    /// evidence of anything -- last night may not have been written to
    /// Health yet, or the sleeper may still be asleep.
    func testYesterdaysNightIsStillCurrentEarlyInTheMorning() throws {
        XCTAssertEqual(try state(nightsAgo: 1, at: 6), .current)
        XCTAssertEqual(try state(nightsAgo: 1, at: SnapshotFreshness.settledHour - 1), .current)
    }

    /// A snapshot dated in the future is a clock disagreement -- a timezone
    /// change mid-flight, most likely -- and shouting about freshness is the
    /// wrong response to it.
    func testASnapshotFromTheFutureIsNotTreatedAsStale() throws {
        XCTAssertEqual(try state(nightsAgo: -1, at: 15), .current)
    }

    // MARK: - Behind

    func testYesterdaysNightIsBehindOnceTheMorningHasSettled() throws {
        XCTAssertEqual(try state(nightsAgo: 1, at: SnapshotFreshness.settledHour), .behind(nights: 1))
        XCTAssertEqual(try state(nightsAgo: 1, at: 15), .behind(nights: 1))
    }

    /// Two nights back is stale at any hour: no amount of "the night may not
    /// have been written yet" explains a two-day gap.
    func testTwoNightsBackIsBehindEvenBeforeTheSettledHour() throws {
        XCTAssertEqual(try state(nightsAgo: 2, at: 6), .behind(nights: 2))
    }

    func testTheGapIsCountedInNights() throws {
        XCTAssertEqual(try state(nightsAgo: 3, at: 15), .behind(nights: 3))
    }

    // MARK: - What it says

    func testACurrentSnapshotHasNothingToSay() {
        XCTAssertNil(SnapshotFreshness.note(for: .current))
        XCTAssertNil(SnapshotFreshness.shortNote(for: .current))
    }

    func testTheNoteNamesTheGapAndTheFix() throws {
        let note = try XCTUnwrap(SnapshotFreshness.note(for: .behind(nights: 2)))
        XCTAssertTrue(note.contains("2 nights ago"), note)
        XCTAssertTrue(note.contains("phone"), note)
    }

    func testASingleNightReadsAsSingular() throws {
        let note = try XCTUnwrap(SnapshotFreshness.note(for: .behind(nights: 1)))
        XCTAssertTrue(note.contains("1 night ago"), note)
        XCTAssertFalse(note.contains("1 nights"), note)
    }

    /// Nothing is updating: the phone app has not run, and the watch cannot
    /// make it run. Copy implying work is underway would have someone wait
    /// for a refresh that is not coming.
    func testTheNoteNeverClaimsSomethingIsInProgress() throws {
        for nights in 1...5 {
            let note = try XCTUnwrap(SnapshotFreshness.note(for: .behind(nights: nights)))
            XCTAssertFalse(note.lowercased().contains("updating"), note)
            XCTAssertFalse(note.lowercased().contains("syncing"), note)
            XCTAssertFalse(note.lowercased().contains("loading"), note)
        }
    }

    func testTheShortNoteFitsAComplicationLine() throws {
        let short = try XCTUnwrap(SnapshotFreshness.shortNote(for: .behind(nights: 3)))
        XCTAssertEqual(short, "3d old")
        XCTAssertLessThanOrEqual(short.count, 8)
    }
}

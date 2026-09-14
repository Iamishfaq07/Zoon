import XCTest

/// One session recorded twice is still one session.
final class WorkoutDeduplicatorTests: XCTestCase {

    private let base = Date(timeIntervalSinceReferenceDate: 0)

    private func candidate(
        _ label: String,
        startSeconds: Double,
        durationSeconds: Double,
        priority: SourcePriority = .phoneOrManual
    ) -> WorkoutDeduplicator.Candidate {
        .init(
            activityLabel: label,
            start: base.addingTimeInterval(startSeconds),
            end: base.addingTimeInterval(startSeconds + durationSeconds),
            priority: priority
        )
    }

    /// The reported case: an Apple Watch run mirrored by a third-party app.
    /// Two UUIDs, near-identical windows, one run.
    func testMirroredSessionCollapsesToOne() {
        let watch = candidate("Run", startSeconds: 0, durationSeconds: 2400, priority: .appleWatch)
        let mirror = candidate("Run", startSeconds: 60, durationSeconds: 2320, priority: .thirdPartyWearable)

        let result = WorkoutDeduplicator.deduplicate([watch, mirror])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, watch.id, "The Watch outranks the mirror")
    }

    /// Two genuine sessions back to back must both survive — the failure
    /// mode a naive start-time tolerance would produce.
    func testBackToBackSessionsBothSurvive() {
        let first = candidate("Run", startSeconds: 0, durationSeconds: 1800)
        let second = candidate("Run", startSeconds: 1800, durationSeconds: 1800)

        XCTAssertEqual(WorkoutDeduplicator.deduplicate([first, second]).count, 2)
    }

    /// Different activities in the same window are different sessions.
    func testDifferentActivitiesAreNotMerged() {
        let run = candidate("Run", startSeconds: 0, durationSeconds: 2400)
        let ride = candidate("Ride", startSeconds: 0, durationSeconds: 2400)

        XCTAssertEqual(WorkoutDeduplicator.deduplicate([run, ride]).count, 2)
    }

    /// Half-overlapping sessions of the same activity are two efforts, not
    /// one duplicate: the overlap is below the threshold on the shorter.
    func testPartialOverlapIsNotADuplicate() {
        let first = candidate("Run", startSeconds: 0, durationSeconds: 2400)
        let second = candidate("Run", startSeconds: 1500, durationSeconds: 2400)

        XCTAssertEqual(WorkoutDeduplicator.deduplicate([first, second]).count, 2)
    }

    /// On equal priority the longer recording wins — the shorter is the one
    /// more likely to have been cut short by a dropped connection.
    func testTieGoesToTheLongerRecording() {
        let short = candidate("Ride", startSeconds: 0, durationSeconds: 3000, priority: .thirdPartyWearable)
        let long = candidate("Ride", startSeconds: 0, durationSeconds: 3600, priority: .thirdPartyWearable)

        let result = WorkoutDeduplicator.deduplicate([short, long])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, long.id)
    }

    /// Priority beats duration: a longer third-party record does not
    /// displace the Watch's own.
    func testPriorityOutranksDuration() {
        let watch = candidate("Run", startSeconds: 0, durationSeconds: 2400, priority: .appleWatch)
        let longer = candidate("Run", startSeconds: 0, durationSeconds: 2600, priority: .thirdPartyWearable)

        XCTAssertEqual(WorkoutDeduplicator.deduplicate([watch, longer]).first?.id, watch.id)
    }

    /// Three writers of one session still collapse to one.
    func testThreeWritersOfOneSession() {
        let a = candidate("Swim", startSeconds: 0, durationSeconds: 1800, priority: .phoneOrManual)
        let b = candidate("Swim", startSeconds: 30, durationSeconds: 1780, priority: .thirdPartyWearable)
        let c = candidate("Swim", startSeconds: 10, durationSeconds: 1800, priority: .appleWatch)

        let result = WorkoutDeduplicator.deduplicate([a, b, c])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, c.id)
    }

    func testEmptyAndSingleAreUnchanged() {
        XCTAssertTrue(WorkoutDeduplicator.deduplicate([]).isEmpty)
        let one = candidate("Walk", startSeconds: 0, durationSeconds: 600)
        XCTAssertEqual(WorkoutDeduplicator.deduplicate([one]).count, 1)
    }

    /// Zero-duration records (a mis-written session) must not multiply.
    func testZeroDurationDuplicatesCollapse() {
        let a = candidate("Yoga", startSeconds: 0, durationSeconds: 0)
        let b = candidate("Yoga", startSeconds: 0, durationSeconds: 0)
        XCTAssertEqual(WorkoutDeduplicator.deduplicate([a, b]).count, 1)
    }

    /// Output is ordered, whatever order the query returned.
    func testResultIsSortedByStart() {
        let late = candidate("Run", startSeconds: 7200, durationSeconds: 1800)
        let early = candidate("Walk", startSeconds: 0, durationSeconds: 1800)

        let result = WorkoutDeduplicator.deduplicate([late, early])
        XCTAssertEqual(result.map(\.id), [early.id, late.id])
    }
}

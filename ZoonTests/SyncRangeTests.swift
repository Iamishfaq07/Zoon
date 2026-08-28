import XCTest

/// Which slices of history a HealthKit delta actually requires rebuilding.
///
/// The sync path used the anchored query as a change gate and nothing more: if
/// anything at all had changed it re-extracted every night in the ninety-day
/// window, and `FeatureExtractor.extract` issues roughly eight HealthKit
/// queries per night. So one corrected nap from last Tuesday cost several
/// hundred queries, and that was the per-observer-callback price.
final class SyncRangeTests: XCTestCase {

    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86_400

    /// A fixed "now" so nothing here depends on the wall clock.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var window: DateInterval {
        DateInterval(start: now.addingTimeInterval(-90 * day), end: now)
    }

    private func at(daysAgo: Double) -> Date {
        now.addingTimeInterval(-daysAgo * day)
    }

    // MARK: - merge

    func testMergingNothingGivesNothing() {
        XCTAssertTrue(SyncRange.merge([]).isEmpty)
    }

    func testOverlappingIntervalsBecomeOne() {
        let a = DateInterval(start: at(daysAgo: 10), end: at(daysAgo: 8))
        let b = DateInterval(start: at(daysAgo: 9), end: at(daysAgo: 6))
        let merged = SyncRange.merge([a, b])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].start, a.start)
        XCTAssertEqual(merged[0].end, b.end)
    }

    func testDisjointIntervalsStaySeparate() {
        let a = DateInterval(start: at(daysAgo: 40), end: at(daysAgo: 39))
        let b = DateInterval(start: at(daysAgo: 5), end: at(daysAgo: 4))
        XCTAssertEqual(SyncRange.merge([a, b]).count, 2)
    }

    func testAnIntervalFullyInsideAnotherIsAbsorbed() {
        let outer = DateInterval(start: at(daysAgo: 10), end: at(daysAgo: 2))
        let inner = DateInterval(start: at(daysAgo: 6), end: at(daysAgo: 5))
        let merged = SyncRange.merge([outer, inner])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].start, outer.start)
        XCTAssertEqual(merged[0].end, outer.end, "the inner interval must not shrink the outer one")
    }

    func testGapToleranceJoinsNearbyIntervals() {
        let a = DateInterval(start: at(daysAgo: 10), end: at(daysAgo: 9))
        let b = DateInterval(start: at(daysAgo: 8), end: at(daysAgo: 7))
        XCTAssertEqual(SyncRange.merge([a, b], gapTolerance: 0).count, 2)
        XCTAssertEqual(SyncRange.merge([a, b], gapTolerance: 2 * day).count, 1)
    }

    func testUnsortedInputIsHandled() {
        let late = DateInterval(start: at(daysAgo: 3), end: at(daysAgo: 2))
        let early = DateInterval(start: at(daysAgo: 30), end: at(daysAgo: 29))
        let merged = SyncRange.merge([late, early])
        XCTAssertEqual(merged.count, 2)
        XCTAssertLessThan(merged[0].start, merged[1].start)
    }

    // MARK: - affected

    func testNoChangesAffectNothing() {
        XCTAssertTrue(SyncRange.affected(changedAt: [], clampedTo: window).isEmpty)
    }

    /// The padding is the whole safety argument: a night is at most ~14 hours,
    /// so 18 hours either side guarantees the night containing the change is
    /// fully inside the range rather than truncated at its edge.
    func testASingleChangeIsPaddedBothWays() {
        let instant = at(daysAgo: 30)
        let ranges = SyncRange.affected(changedAt: [instant], clampedTo: window)

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].start, instant.addingTimeInterval(-SyncRange.contextHours * hour))
        XCTAssertEqual(ranges[0].end, instant.addingTimeInterval(SyncRange.contextHours * hour))
        XCTAssertGreaterThan(ranges[0].duration, 28 * hour, "must comfortably exceed one night")
    }

    func testPaddingIsClampedToTheWindow() {
        let ranges = SyncRange.affected(changedAt: [now], clampedTo: window)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].end, window.end, "cannot pad past the end of the window")
        XCTAssertGreaterThanOrEqual(ranges[0].start, window.start)
    }

    /// A change outside the window is dropped rather than trapping on an
    /// inverted `DateInterval`.
    func testAChangeOutsideTheWindowIsIgnored() {
        XCTAssertTrue(
            SyncRange.affected(changedAt: [at(daysAgo: 400)], clampedTo: window).isEmpty
        )
    }

    func testTwoChangesOnTheSameNightBecomeOneRange() {
        let ranges = SyncRange.affected(
            changedAt: [at(daysAgo: 10), at(daysAgo: 10).addingTimeInterval(4 * hour)],
            clampedTo: window
        )
        XCTAssertEqual(ranges.count, 1)
    }

    func testChangesWeeksApartStaySeparateRanges() {
        let ranges = SyncRange.affected(
            changedAt: [at(daysAgo: 60), at(daysAgo: 10)],
            clampedTo: window
        )
        XCTAssertEqual(ranges.count, 2)
    }

    // MARK: - worthwhileness

    func testASmallRangeIsWorthRebuildingPartially() {
        let ranges = SyncRange.affected(changedAt: [at(daysAgo: 30)], clampedTo: window)
        XCTAssertTrue(SyncRange.isPartialRebuildWorthwhile(ranges, window: window))
    }

    func testRangesCoveringMostOfTheWindowAreNot() {
        let scattered = stride(from: 1.0, through: 80.0, by: 2.0).map { at(daysAgo: $0) }
        let ranges = SyncRange.affected(changedAt: scattered, clampedTo: window)
        XCTAssertFalse(
            SyncRange.isPartialRebuildWorthwhile(ranges, window: window),
            "a delta smeared across the window has no partial path worth taking"
        )
    }

    func testNoRangesIsNotWorthwhile() {
        XCTAssertFalse(SyncRange.isPartialRebuildWorthwhile([], window: window))
    }

    // MARK: - plan

    func testAnEmptyStoreAlwaysRebuildsEverything() {
        XCTAssertEqual(
            SyncRange.plan(changedAt: [at(daysAgo: 1)], hasDeletions: false, storeIsEmpty: true, window: window),
            .full
        )
    }

    /// HealthKit reports deletions as bare UUIDs with no dates, so there is no
    /// instant to build a range around -- and a deletion is exactly the case
    /// that has to reach `prune` over a window wide enough to contain the
    /// night that vanished.
    func testADeletionAlwaysRebuildsEverything() {
        XCTAssertEqual(
            SyncRange.plan(changedAt: [], hasDeletions: true, storeIsEmpty: false, window: window),
            .full
        )
        XCTAssertEqual(
            SyncRange.plan(
                changedAt: [at(daysAgo: 1)], hasDeletions: true, storeIsEmpty: false,
                window: window, recheckFrom: at(daysAgo: 3)
            ),
            .full
        )
    }

    func testNothingChangedAndNoRecheckIsNoWork() {
        XCTAssertEqual(
            SyncRange.plan(changedAt: [], hasDeletions: false, storeIsEmpty: false, window: window),
            .nothingToDo
        )
    }

    /// The load-bearing case, and the reason the recheck floor exists.
    ///
    /// The anchored query is on `sleepAnalysis` alone, so a change to a stored
    /// night's HRV, resting heart rate, respiratory rate, wrist temperature or
    /// breathing disturbances produces an **empty delta**. Without the floor,
    /// a late-HRV observer wakes Zoon up and Zoon does nothing -- the same
    /// outcome as not observing at all.
    func testAPhysiologyOnlyChangeStillRebuildsRecentNights() {
        let plan = SyncRange.plan(
            changedAt: [], hasDeletions: false, storeIsEmpty: false,
            window: window, recheckFrom: at(daysAgo: 3)
        )
        guard case .partial(let ranges) = plan else {
            return XCTFail("expected a partial rebuild of recent nights, got \(plan)")
        }
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].end, window.end)
        XCTAssertEqual(ranges[0].start, at(daysAgo: 3))
    }

    func testTheRecheckFloorIsClampedToTheWindow() {
        let plan = SyncRange.plan(
            changedAt: [], hasDeletions: false, storeIsEmpty: false,
            window: window, recheckFrom: at(daysAgo: 500)
        )
        // Clamped to the window start, which makes it the whole window and so
        // not worth doing partially.
        XCTAssertEqual(plan, .full)
    }

    func testAnOldChangeAndTheRecheckFloorAreSeparateRanges() {
        let plan = SyncRange.plan(
            changedAt: [at(daysAgo: 40)], hasDeletions: false, storeIsEmpty: false,
            window: window, recheckFrom: at(daysAgo: 3)
        )
        guard case .partial(let ranges) = plan else {
            return XCTFail("expected partial, got \(plan)")
        }
        XCTAssertEqual(ranges.count, 2, "a change 40 days back does not merge with the last 3 days")
        XCTAssertLessThan(ranges.reduce(0) { $0 + $1.duration }, window.duration * 0.4)
    }

    /// A change inside the recheck floor should not produce a second range.
    func testARecentChangeMergesIntoTheRecheckFloor() {
        let plan = SyncRange.plan(
            changedAt: [at(daysAgo: 1)], hasDeletions: false, storeIsEmpty: false,
            window: window, recheckFrom: at(daysAgo: 3)
        )
        guard case .partial(let ranges) = plan else {
            return XCTFail("expected partial, got \(plan)")
        }
        XCTAssertEqual(ranges.count, 1)
    }

    func testAScatteredDeltaFallsBackToTheFullWindow() {
        let scattered = stride(from: 1.0, through: 80.0, by: 2.0).map { at(daysAgo: $0) }
        XCTAssertEqual(
            SyncRange.plan(
                changedAt: scattered, hasDeletions: false, storeIsEmpty: false, window: window
            ),
            .full
        )
    }

    /// Applying the plan must not leave work behind that a second identical
    /// pass would find again.
    func testPlanningIsStable() {
        let first = SyncRange.plan(
            changedAt: [at(daysAgo: 10)], hasDeletions: false, storeIsEmpty: false,
            window: window, recheckFrom: at(daysAgo: 3)
        )
        let second = SyncRange.plan(
            changedAt: [at(daysAgo: 10)], hasDeletions: false, storeIsEmpty: false,
            window: window, recheckFrom: at(daysAgo: 3)
        )
        XCTAssertEqual(first, second)
    }
}

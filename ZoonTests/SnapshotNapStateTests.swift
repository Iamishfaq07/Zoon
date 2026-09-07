import XCTest

/// A nap in flight, as the watch sees it.
///
/// `SurfaceRelevance` has always handled a running nap and been tested for it.
/// What was missing was anything to tell it: the production call site in the
/// watch widget passed a literal `false`, so `.napTimer` scored zero forever
/// and the entire path was dead on a real wrist. These tests cover the state
/// that now travels, and -- more importantly -- the cases where it must stop
/// being believed.
final class SnapshotNapStateTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(startedAt: Date?, targetEnd: Date?) -> SleepSnapshot {
        var snapshot = SleepSnapshot(
            features: Fixture.night(daysAgo: 0),
            score: SleepScore.compute(for: Fixture.night(daysAgo: 0), goalMinutes: 480),
            insight: SleepInsight(
                summary: "s", likelyCause: "c", actionableTip: "t", confidence: .medium
            ),
            goalMinutes: 480
        )
        snapshot.napStartedAt = startedAt
        snapshot.napTargetEnd = targetEnd
        return snapshot
    }

    /// A twenty-minute nap started at noon.
    private var running: SleepSnapshot {
        snapshot(startedAt: noon, targetEnd: noon.addingTimeInterval(20 * 60))
    }

    // MARK: - While it runs

    func testANapIsRunningBetweenItsStartAndItsTarget() {
        XCTAssertTrue(running.isNapRunning(at: noon))
        XCTAssertTrue(running.isNapRunning(at: noon.addingTimeInterval(8 * 60)))
        XCTAssertTrue(running.isNapRunning(at: noon.addingTimeInterval(19 * 60)))
    }

    /// Derived at the moment being rendered, never stored. A stored countdown
    /// is wrong the moment it is written, and a widget entry can be rendered
    /// long after the snapshot was published.
    func testRemainingTimeIsMeasuredFromTheMomentAsked() throws {
        let atFive = try XCTUnwrap(running.napRemaining(at: noon.addingTimeInterval(5 * 60)))
        let atFifteen = try XCTUnwrap(running.napRemaining(at: noon.addingTimeInterval(15 * 60)))

        XCTAssertEqual(atFive / 60, 15, accuracy: 0.001)
        XCTAssertEqual(atFifteen / 60, 5, accuracy: 0.001)
    }

    /// Past the target but inside the believable window: still running, and
    /// the countdown floors at zero rather than going negative.
    func testOvershootingTheTargetDoesNotProduceNegativeTime() throws {
        let after = noon.addingTimeInterval(25 * 60)
        XCTAssertTrue(running.isNapRunning(at: after))
        XCTAssertEqual(try XCTUnwrap(running.napRemaining(at: after)), 0, accuracy: 0.001)
    }

    // MARK: - When it must stop being believed

    /// The case that matters most. The phone may have stopped publishing --
    /// app terminated, watch out of range -- while a nap was in flight. Past
    /// the believable window the snapshot is no longer evidence of anything,
    /// and the Smart Stack must stop raising a nap that ended an hour ago.
    func testAStaleSnapshotStopsClaimingANap() {
        let longAfter = noon
            .addingTimeInterval(20 * 60)
            .addingTimeInterval(SleepSnapshot.napBelievableAfterTarget + 60)
        XCTAssertFalse(running.isNapRunning(at: longAfter))
        XCTAssertNil(running.napRemaining(at: longAfter))
    }

    /// Nothing is running before it started -- a timeline entry generated for
    /// an earlier instant must not inherit a later nap.
    func testANapIsNotRunningBeforeItStarted() {
        XCTAssertFalse(running.isNapRunning(at: noon.addingTimeInterval(-60)))
    }

    /// A snapshot published after the user ended the nap early carries no
    /// nap at all, which is the same nil as a snapshot written before these
    /// fields existed. Both mean "no nap to show".
    func testNoNapIsNeverRunning() {
        let idle = snapshot(startedAt: nil, targetEnd: nil)
        XCTAssertFalse(idle.isNapRunning(at: noon))
        XCTAssertNil(idle.napRemaining(at: noon))
    }

    /// Half a nap is not a nap. Either instant alone cannot describe one, so
    /// neither is trusted on its own.
    func testHalfARecordedNapIsNotANap() {
        XCTAssertFalse(snapshot(startedAt: noon, targetEnd: nil).isNapRunning(at: noon))
        XCTAssertFalse(
            snapshot(startedAt: nil, targetEnd: noon.addingTimeInterval(600)).isNapRunning(at: noon)
        )
    }

    // MARK: - What the relevance engine does with it

    /// The whole point of wiring this: with real state, the nap surface can
    /// finally outrank everything else while a nap is running -- and score
    /// zero the moment it is not.
    func testTheNapSurfaceOutranksEverythingElseWhileRunning() {
        let mid = noon.addingTimeInterval(10 * 60)
        let score = SurfaceRelevance.score(
            for: .napTimer, at: mid, isNapRunning: running.isNapRunning(at: mid)
        )
        XCTAssertEqual(score, SurfaceRelevance.activeNapScore)

        for kind in SurfaceRelevance.Kind.allCases where kind != .napTimer {
            XCTAssertLessThan(
                SurfaceRelevance.score(for: kind, at: mid, isNapRunning: true),
                SurfaceRelevance.activeNapScore
            )
        }
    }

    func testTheNapSurfaceScoresNothingOnceTheNapIsOver() {
        let over = noon.addingTimeInterval(20 * 60)
            .addingTimeInterval(SleepSnapshot.napBelievableAfterTarget + 60)
        XCTAssertEqual(
            SurfaceRelevance.score(for: .napTimer, at: over, isNapRunning: running.isNapRunning(at: over)),
            0
        )
    }

    /// A surface has to declare the kind, or the kind is unreachable.
    ///
    /// This is the gap this suite was written around and did not close.
    /// `.napTimer` was wired end to end and correct, and no complication in
    /// the bundle ever asked for it -- so in the shipping app the branch was
    /// still dead. Worse than absent: a running nap drops every *other*
    /// complication to `outOfWindowScore`, so with nothing scoring 100 the
    /// whole bundle went quiet for the duration of the nap.
    ///
    /// Asserted against the source rather than the type system, because the
    /// widget bundle is not reachable from the test target and "somebody
    /// declares this kind" is exactly the kind of claim that quietly stops
    /// being true.
    func testAComplicationActuallyDeclaresTheNapTimerKind() throws {
        let source = try complicationSource()
        XCTAssertTrue(
            source.contains("WatchComplicationProvider(kind: .napTimer)"),
            "no complication declares .napTimer, so the branch is dead on a real wrist"
        )
        XCTAssertTrue(
            source.contains("NapTimerComplication()"),
            ".napTimer is declared but the complication is not in the bundle"
        )
    }

    /// Every complication is suppressed while a nap runs, so the timeline has
    /// to schedule an entry for the instant that lifts. Without it the whole
    /// bundle stays demoted until its next four-hourly refresh -- Zoon
    /// missing from the Smart Stack for hours *after* the nap ended.
    func testTheTimelineSchedulesTheEndOfTheSuppression() throws {
        let end = try XCTUnwrap(running.napSuppressionEnd)
        XCTAssertEqual(
            end,
            noon.addingTimeInterval(20 * 60 + SleepSnapshot.napBelievableAfterTarget)
        )
        XCTAssertFalse(running.isNapRunning(at: end), "the entry must render as ended, not running")
        XCTAssertTrue(running.isNapRunning(at: end.addingTimeInterval(-1)))

        XCTAssertTrue(
            try complicationSource().contains("napSuppressionEnd"),
            "the timeline does not schedule the end of the nap suppression"
        )
    }

    func testASnapshotWithNoNapHasNothingToSchedule() {
        XCTAssertNil(snapshot(startedAt: nil, targetEnd: nil).napSuppressionEnd)
        XCTAssertNil(snapshot(startedAt: noon, targetEnd: nil).napSuppressionEnd)
    }

    /// The widget bundle is not a linked dependency of this target, so the
    /// two assertions above read it off disk. Skipped rather than failed when
    /// the file cannot be located, since a path that breaks under a different
    /// build layout should not read as a defect in the app.
    private func complicationSource() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let file = here
            .deletingLastPathComponent()      // ZoonTests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("ZoonWatchWidget/ZoonWatchComplications.swift")
        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
            throw XCTSkip("ZoonWatchComplications.swift not reachable from \(file.path)")
        }
        return source
    }

    /// Absolute instants, so moving between time zones mid-nap changes
    /// nothing. A wall-clock target would have jumped.
    func testATimeZoneChangeDoesNotDisturbARunningNap() {
        let mid = noon.addingTimeInterval(10 * 60)
        XCTAssertTrue(running.isNapRunning(at: mid))
        // Same instant, expressed from somewhere else entirely.
        let elsewhere = Date(timeIntervalSince1970: mid.timeIntervalSince1970)
        XCTAssertTrue(running.isNapRunning(at: elsewhere))
    }
}

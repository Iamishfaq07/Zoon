import XCTest

/// How a belief changed, kept rather than replaced.
///
/// The two failure modes point in opposite directions, and both are tested:
/// overwriting the previous belief destroys the history, and appending the
/// current belief on every refresh buries the revisions that matter under
/// a thousand identical rows.
final class EvidenceLedgerTests: XCTestCase {

    private let claim = "tag:caffeineLate"

    private func revision(
        at daysAgo: Int,
        status: EvidenceLedger.Status = .associated,
        effect: Double? = 11,
        lower: Double? = 4,
        upper: Double? = 18,
        sampleSize: Int = 17,
        algorithmVersion: Int = 1
    ) -> EvidenceLedger.Revision {
        EvidenceLedger.Revision(
            claimID: claim,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400),
            status: status,
            headline: "Late caffeine, +\(effect ?? 0)m latency",
            effect: effect,
            effectUnit: "minutes",
            uncertaintyLower: lower,
            uncertaintyUpper: upper,
            sampleSize: sampleSize,
            windowStart: nil,
            windowEnd: nil,
            algorithmVersion: algorithmVersion,
            sourceFeature: "sleepLatency",
            provenance: "JournalCorrelator"
        )
    }

    // MARK: - Never erase

    func testTheFirstRevisionIsAlwaysRecorded() {
        let history = EvidenceLedger.recording(revision(at: 30), into: [])
        XCTAssertEqual(history.count, 1)
    }

    func testAStatusChangeIsAlwaysRecorded() {
        var history = EvidenceLedger.recording(revision(at: 30, status: .learning), into: [])
        history = EvidenceLedger.recording(revision(at: 10, status: .associated), into: history)
        history = EvidenceLedger.recording(revision(at: 5, status: .testing), into: history)
        history = EvidenceLedger.recording(revision(at: 1, status: .supported), into: history)

        XCTAssertEqual(
            EvidenceLedger.timeline(for: claim, in: history).map(\.status),
            [.learning, .associated, .testing, .supported]
        )
    }

    /// The case the ledger exists for: a claim that was supported and is not
    /// any more. Both beliefs survive.
    func testChangingItsMindKeepsBothBeliefs() {
        var history = EvidenceLedger.recording(revision(at: 30, status: .supported), into: [])
        history = EvidenceLedger.recording(revision(at: 1, status: .notSupported), into: history)

        let timeline = EvidenceLedger.timeline(for: claim, in: history)
        XCTAssertEqual(timeline.count, 2)
        XCTAssertEqual(timeline.first?.status, .supported, "the earlier belief must not be erased")
        XCTAssertEqual(timeline.last?.status, .notSupported)
    }

    // MARK: - But do not log

    /// Run on every refresh, an unchanged belief must not produce a row.
    func testAnUnchangedBeliefIsNotRecordedAgain() {
        var history = EvidenceLedger.recording(revision(at: 30), into: [])
        for day in stride(from: 29, through: 1, by: -1) {
            history = EvidenceLedger.recording(revision(at: day), into: history)
        }
        XCTAssertEqual(history.count, 1, "29 refreshes of the same belief produced \(history.count) rows")
    }

    /// An effect that moves within the previous interval is the same claim
    /// with more data, not a new one.
    func testAnEffectInsideThePreviousIntervalIsNotANewBelief() {
        let history = EvidenceLedger.recording(revision(at: 30), into: [])
        let nudged = EvidenceLedger.recording(revision(at: 1, effect: 14), into: history)
        XCTAssertEqual(nudged.count, 1)
    }

    func testAnEffectOutsideThePreviousIntervalIsANewBelief() {
        let history = EvidenceLedger.recording(revision(at: 30), into: [])
        let moved = EvidenceLedger.recording(revision(at: 1, effect: 25), into: history)
        XCTAssertEqual(moved.count, 2)
    }

    /// The interval test cannot run for a claim that honestly has no interval,
    /// and three of the four engines writing here are in that position -- a
    /// change point reports separation in standard errors, a twin split
    /// reports two spreads rather than an interval on their difference, an
    /// experiment's before/after medians have no standard error at all.
    /// Without the relative fallback an effect that doubled would sit
    /// unrecorded behind a row saying something else.
    func testAnEffectThatMovesWithoutAnIntervalToJudgeItIsStillANewBelief() {
        let history = EvidenceLedger.recording(
            revision(at: 30, effect: 6, lower: nil, upper: nil), into: []
        )
        let moved = EvidenceLedger.recording(
            revision(at: 1, effect: 9, lower: nil, upper: nil), into: history
        )
        XCTAssertEqual(moved.count, 2, "6 to 9 is half again -- a changed belief")
    }

    func testASmallEffectMoveWithoutAnIntervalIsNotANewBelief() {
        let history = EvidenceLedger.recording(
            revision(at: 30, effect: 6, lower: nil, upper: nil), into: []
        )
        let nudged = EvidenceLedger.recording(
            revision(at: 1, effect: 6.6, lower: nil, upper: nil), into: history
        )
        XCTAssertEqual(nudged.count, 1, "10% is the wobble of a median gaining a night")
    }

    /// An effect of exactly zero has no scale to be relative to, and any move
    /// off it is a claim where there was none.
    func testAMoveOffZeroIsMaterialAndStayingAtZeroIsNot() {
        XCTAssertTrue(EvidenceLedger.Revision.hasShifted(from: 0, to: 0.4))
        XCTAssertFalse(EvidenceLedger.Revision.hasShifted(from: 0, to: 0))
    }

    /// The interval is the better test and stays the first choice. A reading
    /// that doubled but landed inside the previous interval is the same claim
    /// with more data, and the relative fallback must not override that.
    func testTheIntervalStillWinsWhenThereIsOne() {
        let history = EvidenceLedger.recording(
            revision(at: 30, effect: 6, lower: 2, upper: 18), into: []
        )
        let doubled = EvidenceLedger.recording(
            revision(at: 1, effect: 12, lower: 2, upper: 18), into: history
        )
        XCTAssertEqual(doubled.count, 1)
    }

    // MARK: - Materially more evidence

    func testHalfAsMuchDataAgainIsWorthRecording() {
        let history = EvidenceLedger.recording(revision(at: 30, sampleSize: 20), into: [])
        XCTAssertEqual(EvidenceLedger.recording(revision(at: 1, sampleSize: 30), into: history).count, 2)
    }

    func testASmallSampleIncreaseIsNot() {
        let history = EvidenceLedger.recording(revision(at: 30, sampleSize: 20), into: [])
        XCTAssertEqual(EvidenceLedger.recording(revision(at: 1, sampleSize: 24), into: history).count, 1)
    }

    /// A sample that shrinks must never count as growth, however the ratio
    /// falls out -- 0 previous nights would otherwise satisfy any multiple.
    func testAShrinkingSampleIsNotGrowth() {
        let history = EvidenceLedger.recording(revision(at: 30, sampleSize: 0), into: [])
        XCTAssertEqual(EvidenceLedger.recording(revision(at: 1, sampleSize: 0), into: history).count, 1)

        let fromTen = EvidenceLedger.recording(revision(at: 30, sampleSize: 10), into: [])
        XCTAssertEqual(EvidenceLedger.recording(revision(at: 1, sampleSize: 4), into: fromTen).count, 1)
    }

    // MARK: - Algorithm version

    /// An effect computed by a different model is a different claim even at
    /// the same number. This is the same reasoning that gives
    /// SleepIntelligenceScore a currentVersion.
    func testANewAlgorithmVersionIsAlwaysANewRevision() {
        let history = EvidenceLedger.recording(revision(at: 30, algorithmVersion: 1), into: [])
        let rescored = EvidenceLedger.recording(revision(at: 1, algorithmVersion: 2), into: history)
        XCTAssertEqual(rescored.count, 2)
        XCTAssertEqual(rescored.last?.algorithmVersion, 2)
    }

    // MARK: - Reading it back

    func testTimelineReadsOldestFirst() {
        var history: [EvidenceLedger.Revision] = []
        history = EvidenceLedger.recording(revision(at: 1, status: .supported), into: history)
        history = EvidenceLedger.recording(revision(at: 30, status: .learning), into: history)

        let timeline = EvidenceLedger.timeline(for: claim, in: history)
        XCTAssertEqual(timeline.map(\.status), [.learning, .supported], "a timeline only reads forwards")
    }

    func testOneClaimsHistoryDoesNotLeakIntoAnothers() {
        var history = EvidenceLedger.recording(revision(at: 30), into: [])
        var other = revision(at: 20)
        other = EvidenceLedger.Revision(
            claimID: "tag:alcohol", recordedAt: other.recordedAt, status: .learning,
            headline: other.headline, effect: nil, effectUnit: nil,
            uncertaintyLower: nil, uncertaintyUpper: nil, sampleSize: 3,
            windowStart: nil, windowEnd: nil, algorithmVersion: 1,
            sourceFeature: "sleepEfficiency", provenance: "JournalCorrelator"
        )
        history = EvidenceLedger.recording(other, into: history)

        XCTAssertEqual(EvidenceLedger.timeline(for: claim, in: history).count, 1)
        XCTAssertEqual(EvidenceLedger.timeline(for: "tag:alcohol", in: history).count, 1)
        XCTAssertEqual(Set(EvidenceLedger.claimIDs(in: history)), [claim, "tag:alcohol"])
    }

    /// Claims are listed by when they last changed, so the one Zoon most
    /// recently revised is first.
    func testClaimsAreListedMostRecentlyUpdatedFirst() {
        var history = EvidenceLedger.recording(revision(at: 30), into: [])
        let recent = EvidenceLedger.Revision(
            claimID: "tag:alcohol", recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .learning, headline: "", effect: nil, effectUnit: nil,
            uncertaintyLower: nil, uncertaintyUpper: nil, sampleSize: 3,
            windowStart: nil, windowEnd: nil, algorithmVersion: 1,
            sourceFeature: "sleepEfficiency", provenance: "JournalCorrelator"
        )
        history = EvidenceLedger.recording(recent, into: history)
        XCTAssertEqual(EvidenceLedger.claimIDs(in: history).first, "tag:alcohol")
    }

    func testEveryStatusHasALabel() {
        for status in EvidenceLedger.Status.allCases {
            XCTAssertFalse(status.label.isEmpty, "\(status.rawValue) has no label")
        }
    }

    // MARK: - Why did this change?

    /// The spec's own worked example: an association at +3 minutes on low
    /// evidence becomes +11 on more, and the screen says which.
    func testAChangeReportsTheReadingsAndTheReason() throws {
        let before = revision(at: 30, status: .associated, effect: 3, lower: -2, upper: 8, sampleSize: 8)
        let after = revision(at: 2, status: .supported, effect: 11, sampleSize: 17)
        let change = EvidenceLedger.change(from: before, to: after)

        XCTAssertTrue(change.earlierLine.contains("+3 minutes"), change.earlierLine)
        XCTAssertTrue(change.earlierLine.contains("8 nights"), change.earlierLine)
        XCTAssertTrue(change.nowLine.contains("+11 minutes"), change.nowLine)
        XCTAssertTrue(change.nowLine.contains("17 nights"), change.nowLine)
        XCTAssertTrue(change.whyLine.contains("9 new comparable nights were added"), change.whyLine)
    }

    /// A first belief did not change from anything, and saying it did would
    /// invent a history.
    func testTheFirstRevisionOfAClaimHasNoChange() {
        let first = revision(at: 30)
        XCTAssertNil(EvidenceLedger.change(to: first, in: [first]))
    }

    func testAChangeComparesAgainstTheImmediatelyPreviousRevision() throws {
        let oldest = revision(at: 30, status: .learning, effect: nil, sampleSize: 2)
        let middle = revision(at: 20, status: .associated, effect: 3, sampleSize: 8)
        let newest = revision(at: 2, status: .supported, effect: 11, sampleSize: 17)
        let change = try XCTUnwrap(
            EvidenceLedger.change(to: newest, in: [oldest, middle, newest])
        )
        XCTAssertEqual(change.previous, middle, "the comparison must be against the one before it")
    }

    /// An effect from a superseded model is not a larger or smaller version
    /// of the current one -- it is a different measurement, and putting the
    /// two side by side invites a comparison that was never valid.
    func testAMethodChangeSuppressesTheEffectComparison() {
        let before = revision(at: 30, effect: 3, sampleSize: 17, algorithmVersion: 1)
        let after = revision(at: 2, effect: 11, sampleSize: 17, algorithmVersion: 2)
        let change = EvidenceLedger.change(from: before, to: after)

        XCTAssertFalse(change.isComparable)
        XCTAssertFalse(
            change.reasons.contains { if case .effectMoved = $0 { return true } else { return false } },
            "the effect must not be described as having moved across a method change"
        )
        XCTAssertTrue(change.whyLine.contains("method changed"), change.whyLine)
        XCTAssertTrue(change.whyLine.contains("different measurement"), change.whyLine)
    }

    /// Listed first wherever it appears, because it makes every other
    /// comparison in the list meaningless.
    func testAMethodChangeIsTheFirstReasonGiven() throws {
        let before = revision(at: 30, status: .associated, sampleSize: 8, algorithmVersion: 1)
        let after = revision(at: 2, status: .supported, sampleSize: 17, algorithmVersion: 2)
        let change = EvidenceLedger.change(from: before, to: after)

        let first = try XCTUnwrap(change.reasons.first)
        guard case .methodChanged = first else {
            return XCTFail("expected the method change first, got \(first)")
        }
    }

    func testAStatusMoveIsNamedInBothDirections() {
        let forward = EvidenceLedger.change(
            from: revision(at: 30, status: .associated),
            to: revision(at: 2, status: .supported)
        )
        XCTAssertTrue(forward.whyLine.contains("Association detected became Supported"), forward.whyLine)

        // A belief can weaken. Recording that is the entire point of a ledger.
        let backward = EvidenceLedger.change(
            from: revision(at: 30, status: .supported),
            to: revision(at: 2, status: .inconclusive)
        )
        XCTAssertTrue(backward.whyLine.contains("Supported became Inconclusive"), backward.whyLine)
    }

    /// A shrinking sample is unusual -- a window rolling past old nights, an
    /// entry deleted -- and is exactly the case where a silently moving
    /// number would look like new evidence.
    func testASmallerSampleIsStatedNotHidden() {
        let change = EvidenceLedger.change(
            from: revision(at: 30, sampleSize: 20),
            to: revision(at: 2, sampleSize: 14)
        )
        XCTAssertTrue(change.whyLine.contains("6 nights dropped out"), change.whyLine)
    }

    func testAnUnchangedBeliefHasNothingToExplain() {
        let same = revision(at: 30)
        let change = EvidenceLedger.change(from: same, to: revision(at: 2))
        XCTAssertTrue(change.reasons.isEmpty)
        XCTAssertTrue(change.whyLine.isEmpty)
    }

    func testASingleAddedNightReadsAsSingular() {
        let change = EvidenceLedger.change(
            from: revision(at: 30, sampleSize: 16),
            to: revision(at: 2, sampleSize: 17)
        )
        XCTAssertTrue(change.whyLine.contains("1 new comparable night was added"), change.whyLine)
    }

    // MARK: - Reading an effect

    /// The sign is the finding: "3 minutes" does not say whether the night
    /// got better or worse.
    func testAnEffectIsAlwaysSigned() {
        XCTAssertEqual(EvidenceLedger.Change.formatted(3, unit: "minutes"), "+3 minutes")
        XCTAssertEqual(EvidenceLedger.Change.formatted(-11, unit: "minutes"), "-11 minutes")
    }

    func testAFractionalEffectKeepsOneDecimal() {
        XCTAssertEqual(EvidenceLedger.Change.formatted(9.24, unit: "minutes"), "+9.2 minutes")
        // Swift's `rounded()` is half-away-from-zero, not banker's rounding.
        XCTAssertEqual(EvidenceLedger.Change.formatted(9.25, unit: "minutes"), "+9.3 minutes")
    }

    func testAnEffectWithNoUnitIsStillReadable() {
        XCTAssertEqual(EvidenceLedger.Change.formatted(5, unit: nil), "+5")
    }

    // MARK: - Withdrawing a claim

    /// The engines only offer current beliefs, so a finding that stops being
    /// produced says nothing, and its last "Association detected" stands
    /// until something withdraws it.
    func testAStandingAssociationNoLongerFoundIsOwedARetraction() {
        let history = [revision(at: 30, status: .learning), revision(at: 10, status: .associated)]
        let owed = EvidenceLedger.associationsToRetract(
            in: history, currentClaimIDs: ["tag:alcohol"], provenance: "JournalCorrelator"
        )
        XCTAssertEqual(owed.map(\.claimID), [claim])
        XCTAssertEqual(owed.first?.status, .associated)
    }

    func testAssociationsStillFoundNeverMadeOrAlreadyWithdrawnAreLeftAlone() {
        let stillFound = EvidenceLedger.associationsToRetract(
            in: [revision(at: 10)], currentClaimIDs: [claim], provenance: "JournalCorrelator"
        )
        XCTAssertTrue(stillFound.isEmpty)

        let onlyLearning = EvidenceLedger.associationsToRetract(
            in: [revision(at: 10, status: .learning)], currentClaimIDs: [], provenance: "JournalCorrelator"
        )
        XCTAssertTrue(onlyLearning.isEmpty, "learning asserts nothing there is to withdraw")

        let alreadyWithdrawn = EvidenceLedger.associationsToRetract(
            in: [revision(at: 10), revision(at: 1, status: .inconclusive)],
            currentClaimIDs: [], provenance: "JournalCorrelator"
        )
        XCTAssertTrue(alreadyWithdrawn.isEmpty, "the latest revision decides, not any earlier one")

        let otherEngine = EvidenceLedger.associationsToRetract(
            in: [revision(at: 10)], currentClaimIDs: [], provenance: "ZoonTwin"
        )
        XCTAssertTrue(otherEngine.isEmpty, "one engine cannot withdraw another's claim")
    }

    /// A retraction carries no effect -- there is no finding to take one
    /// from -- and lands as a status change, which the ledger always keeps.
    func testARetractionCarriesNoEffectAndIsRecordedAsAStatusChange() throws {
        let standing = revision(at: 10)
        let retraction = EvidenceLedger.retraction(
            of: standing, status: .inconclusive, sampleSize: 21,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(retraction.claimID, claim)
        XCTAssertEqual(retraction.status, .inconclusive)
        XCTAssertNil(retraction.effect)
        XCTAssertEqual(retraction.sampleSize, 21)
        XCTAssertEqual(retraction.provenance, standing.provenance)
        XCTAssertTrue(retraction.headline.contains("washed out"), retraction.headline)

        let history = EvidenceLedger.recording(retraction, into: [standing])
        XCTAssertEqual(history.count, 2)
        let change = try XCTUnwrap(EvidenceLedger.change(to: retraction, in: history))
        XCTAssertTrue(change.whyLine.contains("Association detected became Inconclusive"), change.whyLine)
    }
}

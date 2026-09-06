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
}

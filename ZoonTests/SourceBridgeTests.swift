import XCTest
import HealthKit

/// The adversarial case V8 Task 6 exists for: one malformed sample from one
/// source silently restructuring a *different* source's nights.
///
/// ## Why these test the seams rather than `buildSessions`
///
/// `HKCategorySample` has no public API for setting `sourceRevision` on an
/// unsaved sample — it is always synthesized from the running process — so
/// every sample built in a test bundle reports the same source, and the
/// multi-source branch of `buildSessions` can never activate in-process.
/// That is a real limit, and it is why the previous implementation's
/// cross-source bridging survived unnoticed: the only code path that could
/// expose it was the one the tests could not reach.
///
/// The fix was therefore built with its seams exposed as `static` functions
/// over plain values. `clusterByGap`, `overlapGroups` and `qualityScore` take
/// samples and candidates rather than reading a source out of the
/// environment, so each stage of the pipeline is checkable even though the
/// assembled whole is not. What is *not* claimed here: that the end-to-end
/// multi-source selection has been verified on real HealthKit data. It has
/// not, and it cannot be from a unit test.
final class SourceBridgeTests: XCTestCase {

    private let calendar = Calendar.current

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func sample(
        _ stage: HKCategoryValueSleepAnalysis,
        _ start: Date,
        _ end: Date
    ) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: stage.rawValue,
            start: start,
            end: end
        )
    }

    private func candidate(_ samples: [HKCategorySample]) -> SleepSessionBuilder.Candidate {
        SleepSessionBuilder.Candidate(samples: samples)
    }

    // MARK: - Clustering is per source

    /// A source's own samples still split on the gap threshold. This is the
    /// property that used to be applied across all sources at once.
    func testClusterByGapSplitsOnTheThreshold() {
        let samples = [
            sample(.asleepCore, date(1, 23), date(2, 7)),
            sample(.asleepCore, date(2, 23), date(3, 7))
        ]

        let clusters = SleepSessionBuilder.clusterByGap(samples, threshold: 60 * 60)

        XCTAssertEqual(clusters.count, 2, "16 waking hours is well past the gap threshold.")
    }

    func testClusterByGapKeepsAShortGapTogether() {
        let samples = [
            sample(.asleepCore, date(1, 23), date(2, 3)),
            sample(.asleepCore, date(2, 3), date(2, 7))
        ]

        let clusters = SleepSessionBuilder.clusterByGap(samples, threshold: 60 * 60)

        XCTAssertEqual(clusters.count, 1)
    }

    // MARK: - The bridge

    /// Two genuine nights from one source, plus a single 20-hour block from
    /// another that spans the gap between them.
    ///
    /// All three land in one overlap group — correctly, since they are rival
    /// accounts of one span. The bridge is undone at selection, not here:
    /// grouping's job is only to put the competitors in the same room.
    func testAMalformedLongSampleGroupsWithTheNightsItSpans() {
        let nightOne = candidate([sample(.asleepCore, date(1, 23), date(2, 7))])
        let nightTwo = candidate([sample(.asleepCore, date(2, 23), date(3, 7))])
        let bridge = candidate([sample(.asleepUnspecified, date(2, 6), date(3, 2))])

        let groups = SleepSessionBuilder.overlapGroups(in: [nightOne, bridge, nightTwo])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.count, 3)
    }

    /// The decisive assertion. The two clean staged nights must outscore the
    /// 20-hour block, because selection returns *every* candidate from the
    /// winning source — so if the clean pair wins, both nights survive as two
    /// episodes and the bridge is discarded.
    ///
    /// Under the previous implementation this comparison did not exist:
    /// `productType != nil` was a hard tier, so provenance decided the winner
    /// before anyone looked at whether the samples were plausible.
    func testCleanStagedNightsOutscoreATwentyHourBlock() {
        let cleanPair = [
            candidate([sample(.asleepCore, date(1, 23), date(2, 7))]),
            candidate([sample(.asleepCore, date(2, 23), date(3, 7))])
        ]
        let bridge = [candidate([sample(.asleepUnspecified, date(2, 6), date(3, 2))])]

        XCTAssertGreaterThan(
            SleepSessionBuilder.qualityScore(for: cleanPair),
            SleepSessionBuilder.qualityScore(for: bridge)
        )
    }

    /// Non-overlapping candidates must stay in separate groups, or the
    /// grouping step would reintroduce the very merging it exists to prevent.
    func testNonOverlappingCandidatesStayApart() {
        let groups = SleepSessionBuilder.overlapGroups(in: [
            candidate([sample(.asleepCore, date(1, 23), date(2, 7))]),
            candidate([sample(.asleepCore, date(2, 23), date(3, 7))])
        ])

        XCTAssertEqual(groups.count, 2)
    }

    // MARK: - Quality scoring

    /// Plausibility has to be graded, not a cliff edge: a long-but-real
    /// 11-hour night should not be lumped in with a 20-hour impossibility.
    func testAnImplausiblyLongSpanScoresBelowALongButRealOne() {
        let realLongNight = [candidate([sample(.asleepCore, date(1, 21), date(2, 8))])]
        let impossible = [candidate([sample(.asleepCore, date(1, 4), date(2, 4))])]

        XCTAssertGreaterThan(
            SleepSessionBuilder.qualityScore(for: realLongNight),
            SleepSessionBuilder.qualityScore(for: impossible)
        )
    }

    /// A source that claims a long span but reports almost no sleep in it is
    /// describing something other than a night.
    func testSparseCoverageScoresBelowDenseCoverage() {
        let dense = [candidate([sample(.asleepCore, date(1, 23), date(2, 7))])]
        let sparse = [candidate([
            sample(.inBed, date(1, 23), date(2, 7)),
            sample(.asleepCore, date(1, 23), date(1, 23).addingTimeInterval(20 * 60))
        ])]

        XCTAssertGreaterThan(
            SleepSessionBuilder.qualityScore(for: dense),
            SleepSessionBuilder.qualityScore(for: sparse)
        )
    }

    /// Staged sleep is the heaviest term, so a source that distinguishes
    /// core/deep/REM beats one writing undifferentiated "asleep" over the
    /// same span.
    func testStagedSleepOutscoresUndifferentiatedSleep() {
        let staged = [candidate([
            sample(.asleepCore, date(1, 23), date(2, 2)),
            sample(.asleepDeep, date(2, 2), date(2, 4)),
            sample(.asleepREM, date(2, 4), date(2, 7))
        ])]
        let unspecified = [candidate([sample(.asleepUnspecified, date(1, 23), date(2, 7))])]

        XCTAssertGreaterThan(
            SleepSessionBuilder.qualityScore(for: staged),
            SleepSessionBuilder.qualityScore(for: unspecified)
        )
    }

    /// An empty candidate list must score zero rather than trapping on the
    /// division in `stagedFraction`.
    func testEmptyCandidatesScoreZeroWithoutTrapping() {
        XCTAssertEqual(SleepSessionBuilder.qualityScore(for: []), 0)
    }
}

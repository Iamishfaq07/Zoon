import XCTest

/// Covers the nightly decomposition of a shortfall into the two things that
/// can cause it.
///
/// The arithmetic is an identity:
///
///     need − asleep = (need − opportunity) + (opportunity − asleep)
///
/// and the point of showing it is that two people can both be forty minutes
/// short and need opposite advice. One went to bed late; one was in bed for
/// nine hours and awake for two of them. "More time in bed" is the whole
/// answer for the first and actively wrong for the second.
final class SleepOpportunityTests: XCTestCase {

    private func night(
        inBed: Double,
        asleep: Double,
        estimatedInBed: Bool = false,
        daysAgo: Int = 0
    ) -> SleepNightFeatures {
        Fixture.night(
            daysAgo: daysAgo,
            timeAsleepMinutes: asleep,
            timeInBedMinutes: inBed,
            timeInBedIsEstimated: estimatedInBed
        )
    }

    private func make(
        inBed: Double,
        asleep: Double,
        need: Double = 465,
        estimatedInBed: Bool = false,
        history: [SleepNightFeatures] = []
    ) -> SleepOpportunity? {
        SleepOpportunity.make(
            night: night(inBed: inBed, asleep: asleep, estimatedInBed: estimatedInBed),
            needMinutes: need,
            history: history
        )
    }

    // MARK: - The identity

    func testTheTwoGapsSumToTheShortfall() throws {
        let opportunity = try XCTUnwrap(make(inBed: 420, asleep: 390, need: 465))
        XCTAssertEqual(
            opportunity.opportunityGapMinutes + opportunity.executionGapMinutes,
            opportunity.shortfallMinutes,
            accuracy: 0.001
        )
    }

    /// A window longer than the need gives a negative opportunity gap, which
    /// is a real and good answer and must not be clamped away — clamping it
    /// would break the identity above.
    func testAGenerousWindowGivesANegativeOpportunityGap() throws {
        let opportunity = try XCTUnwrap(make(inBed: 485, asleep: 400, need: 450))
        XCTAssertLessThan(opportunity.opportunityGapMinutes, 0)
        XCTAssertEqual(
            opportunity.opportunityGapMinutes + opportunity.executionGapMinutes,
            opportunity.shortfallMinutes,
            accuracy: 0.001
        )
    }

    // MARK: - Attribution

    /// The brief's first example: 7h45 need, 6h55 opportunity, 6h31 actual.
    func testALimitedWindowIsAttributedToOpportunity() throws {
        let opportunity = try XCTUnwrap(make(inBed: 415, asleep: 391, need: 465))
        XCTAssertEqual(opportunity.cause, .opportunity)
        let sentence = try XCTUnwrap(opportunity.sentence)
        XCTAssertTrue(sentence.contains("time available"), sentence)
    }

    /// The brief's second: 7h30 need, 8h05 opportunity, 6h40 actual.
    func testEnoughTimeButPoorContinuityIsAttributedToExecution() throws {
        let opportunity = try XCTUnwrap(make(inBed: 485, asleep: 400, need: 450))
        XCTAssertEqual(opportunity.cause, .execution)
        let sentence = try XCTUnwrap(opportunity.sentence)
        XCTAssertTrue(sentence.contains("allowed enough time"), sentence)
    }

    func testAShortfallFromBothSidesNamesBoth() throws {
        // Forty short on the window, forty-five awake in it.
        let opportunity = try XCTUnwrap(make(inBed: 425, asleep: 380, need: 465))
        XCTAssertEqual(opportunity.cause, .both)
        let sentence = try XCTUnwrap(opportunity.sentence)
        XCTAssertTrue(sentence.contains("both sides"), sentence)
    }

    func testMeetingTheNeedHasNothingToExplain() throws {
        let opportunity = try XCTUnwrap(make(inBed: 500, asleep: 470, need: 465))
        XCTAssertNil(opportunity.cause)
        XCTAssertNil(opportunity.sentence)
        XCTAssertEqual(opportunity.shortfallMinutes, 0)
    }

    /// Sleep need is itself an estimate to within tens of minutes, so a
    /// ten-minute miss is not a finding.
    func testATinyMissIsNotAFinding() throws {
        let opportunity = try XCTUnwrap(make(inBed: 470, asleep: 455, need: 465))
        XCTAssertNil(opportunity.cause)
    }

    // MARK: - The refusal that matters

    /// An inferred time in bed sits close to asleep time by construction, so
    /// the execution gap it produces is not a measurement. Attributing from
    /// it would make every fragmentation problem look like a scheduling one.
    func testAnEstimatedTimeInBedRefusesToAttribute() throws {
        let opportunity = try XCTUnwrap(
            make(inBed: 415, asleep: 391, need: 465, estimatedInBed: true)
        )
        XCTAssertNil(opportunity.cause)
        let sentence = try XCTUnwrap(opportunity.sentence)
        XCTAssertTrue(sentence.contains("estimated"), sentence)
        // The numbers are still reported; only the attribution is withheld.
        XCTAssertEqual(opportunity.shortfallMinutes, 74, accuracy: 0.001)
    }

    // MARK: - Comparative claims need something to compare against

    /// "Lower than usual" may not be said without a usual.
    func testLowerThanUsualIsNotSaidWithoutABaseline() throws {
        let opportunity = try XCTUnwrap(make(inBed: 485, asleep: 400, need: 450))
        XCTAssertNil(opportunity.typicalEfficiencyPercent)
        XCTAssertFalse(opportunity.isBelowUsualEfficiency)
        XCTAssertFalse(try XCTUnwrap(opportunity.sentence).contains("usual"))
    }

    func testLowerThanUsualIsSaidWhenItIsTrue() throws {
        // Ten nights at ~95% efficiency, then one at 82%.
        let history = (1...10).map { night(inBed: 480, asleep: 456, daysAgo: $0) }
        let opportunity = try XCTUnwrap(
            make(inBed: 485, asleep: 400, need: 450, history: history)
        )
        XCTAssertNotNil(opportunity.typicalEfficiencyPercent)
        XCTAssertTrue(opportunity.isBelowUsualEfficiency)
        XCTAssertTrue(try XCTUnwrap(opportunity.sentence).contains("usual"))
    }

    /// A thin baseline is no baseline. Three nights is not a usual.
    func testAThinHistoryDoesNotProduceAUsual() throws {
        let history = (1...3).map { night(inBed: 480, asleep: 456, daysAgo: $0) }
        let opportunity = try XCTUnwrap(
            make(inBed: 485, asleep: 400, need: 450, history: history)
        )
        XCTAssertNil(opportunity.typicalEfficiencyPercent)
    }

    /// Nights whose time in bed was inferred cannot define a usual
    /// efficiency either — their efficiency is an artefact of the inference.
    func testEstimatedNightsAreExcludedFromTheBaseline() throws {
        let history = (1...10).map {
            night(inBed: 480, asleep: 456, estimatedInBed: true, daysAgo: $0)
        }
        let opportunity = try XCTUnwrap(
            make(inBed: 485, asleep: 400, need: 450, history: history)
        )
        XCTAssertNil(opportunity.typicalEfficiencyPercent)
    }

    // MARK: - Guards

    func testNoNeedMeansNoDecomposition() {
        XCTAssertNil(make(inBed: 480, asleep: 420, need: 0))
    }

    func testNoTimeInBedMeansNoDecomposition() {
        XCTAssertNil(make(inBed: 0, asleep: 420))
    }

    func testEfficiencyIsBoundedAtAHundred() throws {
        // Asleep longer than in bed should not produce 104%.
        let opportunity = try XCTUnwrap(make(inBed: 400, asleep: 420))
        XCTAssertLessThanOrEqual(opportunity.efficiencyPercent, 100)
        XCTAssertEqual(opportunity.executionGapMinutes, 0)
    }
}

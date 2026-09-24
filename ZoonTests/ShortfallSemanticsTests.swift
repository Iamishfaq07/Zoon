import XCTest

/// Shortfall, named by when it is measured, and the Coach bug that mixing
/// them up caused.
///
/// A night's stored `sleepDebtMinutes` is the shortfall *entering* it. Coach
/// read that figure and, when it was small, said "last night did not add to
/// your sleep debt" -- a claim about a night the figure does not include.
final class ShortfallSemanticsTests: XCTestCase {

    private func night(
        daysAgo: Int = 0,
        asleep: Double,
        entering: Double,
        need: Double? = 480
    ) -> SleepNightFeatures {
        var night = Fixture.night(
            daysAgo: daysAgo,
            timeAsleepMinutes: asleep,
            timeInBedMinutes: asleep + 20,
            sleepDebtMinutes: entering
        )
        night.sleepNeedBaselineMinutes = need
        return night
    }

    private func behind(_ night: SleepNightFeatures, history: [SleepNightFeatures] = []) -> CoachEvidence.Reply {
        CoachEvidence(night: night, history: history).reply(to: "Am I behind on sleep?")
    }

    // MARK: - Accessors

    func testBeforeIsTheStoredValue() {
        XCTAssertEqual(night(asleep: 400, entering: 37).shortfallBeforeNightMinutes, 37)
    }

    func testAddedIsTheNightsOwnGapAgainstItsOwnNeed() {
        XCTAssertEqual(night(asleep: 400, entering: 0).shortfallAddedByNightMinutes, 80)
        XCTAssertEqual(night(asleep: 520, entering: 0).shortfallAddedByNightMinutes, 0)
        XCTAssertNil(night(asleep: 400, entering: 0, need: nil).shortfallAddedByNightMinutes,
                     "without the night's own need there is no honest gap")
    }

    func testThroughIsOneLedgerStepFromBefore() throws {
        let n = night(asleep: 400, entering: 100)
        let through = try XCTUnwrap(n.shortfallThroughNightMinutes)
        XCTAssertEqual(through, 100 * RecentSleepShortfall.decayPerNight + 80, accuracy: 0.001)
        XCTAssertNil(night(asleep: 400, entering: 100, need: nil).shortfallThroughNightMinutes)
    }

    /// The step the accessors use is the step the history series uses.
    func testTheStepMatchesTheSeries() throws {
        let series = RecentSleepShortfall.debtSeries(
            timeAsleepMinutesOldestFirst: [400, 300, 520],
            goalMinutes: 480
        )
        var ledger = 0.0
        for minutes in [400.0, 300, 520] {
            ledger = RecentSleepShortfall.step(enteringMinutes: ledger, needMinutes: 480, asleepMinutes: minutes)
        }
        XCTAssertEqual(try XCTUnwrap(series.last), ledger, accuracy: 0.0001)
    }

    // MARK: - Coach

    /// Zero shortfall entering, a 5h30 night: the night added to it, and
    /// Coach says so rather than "did not add".
    func testAShortNightAfterACleanRunIsSaidToHaveAdded() {
        let reply = behind(night(asleep: 330, entering: 0))
        XCTAssertFalse(reply.text.lowercased().contains("did not add"), reply.text)
        XCTAssertTrue(reply.text.contains("from this night"), reply.text)
        XCTAssertTrue(reply.text.lowercased().hasPrefix("yes"), reply.text)
    }

    func testAModestlyShortNightAddsEvenWhenTheTotalIsSmall() {
        let reply = behind(night(asleep: 450, entering: 0))
        XCTAssertFalse(reply.text.lowercased().contains("did not add"), reply.text)
        XCTAssertTrue(reply.text.contains("did add"), reply.text)
    }

    /// Carrying shortfall in, then a long night: Coach reports the running
    /// total but does not claim the long night added to it.
    func testALongNightIsNotBlamedForTheShortfallItInherited() {
        let reply = behind(night(asleep: 540, entering: 120))
        XCTAssertTrue(reply.text.lowercased().hasPrefix("yes"), reply.text)
        XCTAssertFalse(reply.text.contains("from this night"), reply.text)
        XCTAssertFalse(reply.text.contains("did add"), reply.text)
        XCTAssertTrue(reply.text.contains("met or came close to your need"), reply.text)
    }

    func testAMetNeedIsSaidToHaveNotAdded() {
        let reply = behind(night(asleep: 490, entering: 0))
        XCTAssertTrue(reply.text.lowercased().hasPrefix("no"), reply.text)
        XCTAssertTrue(reply.text.contains("did not add"), reply.text)
    }

    /// Without the need the night was measured against, Coach will not say
    /// whether the night added anything.
    func testAnUnknownNeedMakesNoClaimAboutTheNight() {
        let reply = behind(night(asleep: 330, entering: 0, need: nil))
        XCTAssertFalse(reply.text.contains("did not add"), reply.text)
        XCTAssertTrue(reply.text.contains("can't say"), reply.text)
    }

    /// A question about an older night answers with that night's figure as
    /// of that morning, never today's.
    func testAHistoricalNightUsesItsOwnFigure() throws {
        let older = night(daysAgo: 3, asleep: 300, entering: 0)      // through 180m
        let newer = night(daysAgo: 0, asleep: 540, entering: 400)    // through ~373m
        let reply = behind(older, history: [newer])
        let olderThrough = try XCTUnwrap(older.shortfallThroughNightMinutes)
        XCTAssertTrue(reply.text.contains(SleepNightFeatures.formatMinutes(olderThrough)), reply.text)
        let newerThrough = try XCTUnwrap(newer.shortfallThroughNightMinutes)
        XCTAssertFalse(reply.text.contains(SleepNightFeatures.formatMinutes(newerThrough)), reply.text)
    }

    func testTheEvidenceLineNamesWhenTheFigureApplies() {
        let known = CoachEvidence(night: night(asleep: 400, entering: 30), history: [])
        XCTAssertEqual(known.catalog["debt"]?.hasPrefix("Recent shortfall after this night"), true)
        let unknown = CoachEvidence(night: night(asleep: 400, entering: 30, need: nil), history: [])
        XCTAssertEqual(unknown.catalog["debt"]?.hasPrefix("Recent shortfall entering this night"), true)
    }
}

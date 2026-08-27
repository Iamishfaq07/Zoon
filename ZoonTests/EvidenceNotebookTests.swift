import XCTest

final class EvidenceNotebookTests: XCTestCase {

    private func day(_ daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
    }

    private func outcome(daysAgo: Int, tag: String = "alcohol") -> SleepExperimentStore.Outcome {
        SleepExperimentStore.Outcome(
            id: UUID(), tag: tag, hypothesis: nil,
            startDate: day(daysAgo + 14), endDate: day(daysAgo),
            metricLabel: "sleep sufficiency",
            baselineMedian: 78, trialMedian: 86,
            baselineNightCount: 14, trialNightCount: 14,
            higherIsBetter: true, trialKnownNightCount: 14
        )
    }

    private func changePoint(daysAgo: Int) throws -> ChangePointDetector.Result {
        var generator = SeededGenerator(seed: 3)
        let nights = (0..<40).map { index -> SleepNightFeatures in
            let base: Double = index < 20 ? 400 : 480
            let asleep = base + generator.nextDouble(in: -8...8)
            return Fixture.night(
                daysAgo: 40 - index + daysAgo,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep / 0.9
            )
        }.sorted { $0.date < $1.date }
        return try XCTUnwrap(ChangePointDetector.detect(nights: nights, metric: .duration))
    }

    private func nightReport() throws -> NightDetective.Report {
        var generator = SeededGenerator(seed: 11)
        let history = (0..<30).map { index in
            Fixture.night(
                daysAgo: 30 - index,
                timeAsleepMinutes: 450 + generator.nextDouble(in: -6...6),
                timeInBedMinutes: 500
            )
        }.sorted { $0.date < $1.date }
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 250, timeInBedMinutes: 500)
        return try XCTUnwrap(NightDetective.investigate(night: night, history: history))
    }

    // MARK: - The hierarchy

    func testStrengthOrdersWeakestToStrongest() {
        XCTAssertLessThan(EvidenceNotebook.Strength.anecdote, .observed)
        XCTAssertLessThan(EvidenceNotebook.Strength.observed, .associated)
        XCTAssertLessThan(EvidenceNotebook.Strength.associated, .tested)
    }

    /// The reason the type exists: a change noticed this morning must not
    /// outrank an experiment the person actually planned and ran, however
    /// much fresher it is.
    func testATestedResultOutranksAMoreRecentObservedChange() throws {
        let entries = EvidenceNotebook.compile(
            experiments: [outcome(daysAgo: 90)],
            changePoints: [try changePoint(daysAgo: 0)]
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.strength, .tested)
        XCTAssertEqual(entries.last?.strength, .observed)
    }

    func testEveryTierSortsAboveTheOneBelowIt() throws {
        let entries = EvidenceNotebook.compile(
            experiments: [outcome(daysAgo: 200)],
            changePoints: [try changePoint(daysAgo: 0)],
            nightReport: try nightReport()
        )

        let strengths = entries.map(\.strength)
        XCTAssertEqual(strengths, strengths.sorted(by: >))
        XCTAssertEqual(strengths.first, .tested)
        XCTAssertEqual(strengths.last, .anecdote)
    }

    /// Recency is the tie-breaker, never the primary key.
    func testWithinATierTheMoreRecentClaimComesFirst() {
        let older = outcome(daysAgo: 100)
        let newer = outcome(daysAgo: 2)

        let entries = EvidenceNotebook.compile(experiments: [older, newer])

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.id, "experiment-\(newer.id.uuidString)")
    }

    // MARK: - Caveats

    func testEveryTierCarriesItsOwnCaveat() {
        let caveats = EvidenceNotebook.Strength.allCases.map(\.caveat)
        XCTAssertEqual(Set(caveats).count, EvidenceNotebook.Strength.allCases.count,
                       "each tier needs its own wording, not a shared one")
        XCTAssertTrue(caveats.allSatisfy { !$0.isEmpty })
    }

    /// A single night must never be dressed up as a pattern.
    func testTheAnecdoteCaveatRefusesToCallOneNightEvidence() {
        let caveat = EvidenceNotebook.Strength.anecdote.caveat
        XCTAssertTrue(caveat.contains("One night"), caveat)
        XCTAssertTrue(caveat.lowercased().contains("not evidence"), caveat)
    }

    /// An observed change describes history and explains nothing.
    func testTheObservedCaveatDisclaimsCause() {
        let caveat = EvidenceNotebook.Strength.observed.caveat
        XCTAssertTrue(caveat.lowercased().contains("nothing here says what changed it"), caveat)
    }

    /// Even the strongest tier is not a controlled trial, and must not imply
    /// it is.
    func testNoCaveatClaimsAControlledOrProvenResult() {
        for strength in EvidenceNotebook.Strength.allCases {
            let text = strength.caveat.lowercased()
            XCTAssertFalse(text.contains("proves"), strength.caveat)
            XCTAssertFalse(text.contains("causes"), strength.caveat)
        }
        XCTAssertTrue(
            EvidenceNotebook.Strength.associated.caveat.lowercased()
                .contains("not a controlled test")
        )
    }

    // MARK: - Compilation

    func testEmptyInputsCompileToAnEmptyNotebook() {
        XCTAssertTrue(EvidenceNotebook.compile().isEmpty)
    }

    /// Only the single strongest factor from a night is admitted -- otherwise
    /// one unusual night floods the notebook with its weakest possible claims.
    func testOnlyOneEntryIsTakenFromANightReport() throws {
        let report = try nightReport()
        XCTAssertGreaterThan(report.factors.count, 1, "precondition: several factors stood out")

        let entries = EvidenceNotebook.compile(nightReport: report)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.strength, .anecdote)
    }

    func testAnUnremarkableNightContributesNothing() throws {
        var generator = SeededGenerator(seed: 5)
        let history = (0..<30).map { index in
            Fixture.night(
                daysAgo: 30 - index,
                timeAsleepMinutes: 450 + generator.nextDouble(in: -6...6),
                timeInBedMinutes: 500
            )
        }.sorted { $0.date < $1.date }
        let ordinary = Fixture.night(daysAgo: 0, timeAsleepMinutes: 450, timeInBedMinutes: 500)
        let report = try XCTUnwrap(
            NightDetective.investigate(night: ordinary, history: history)
        )

        XCTAssertTrue(report.isUnremarkable, "precondition")
        XCTAssertTrue(EvidenceNotebook.compile(nightReport: report).isEmpty)
    }

    func testEntryIdsAreUniqueAcrossSources() throws {
        let entries = EvidenceNotebook.compile(
            experiments: [outcome(daysAgo: 10), outcome(daysAgo: 40, tag: "caffeineLate")],
            changePoints: [try changePoint(daysAgo: 0)],
            nightReport: try nightReport()
        )
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
    }

    func testAnExperimentHeadlineNamesTheBehaviourAndDirection() throws {
        let entries = EvidenceNotebook.compile(experiments: [outcome(daysAgo: 5)])
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.strength, .tested)
        XCTAssertTrue(entry.headline.contains("Alcohol"), entry.headline)
        XCTAssertTrue(entry.headline.contains("improved"), entry.headline)
    }

    /// An unrecognised stored tag must degrade to its raw identifier rather
    /// than vanishing from the notebook.
    func testAnUnknownStoredTagFallsBackToItsRawIdentifier() throws {
        let entries = EvidenceNotebook.compile(
            experiments: [outcome(daysAgo: 5, tag: "somethingRetired")]
        )
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entry.headline.contains("somethingRetired"), entry.headline)
    }
}

import XCTest

final class NightDetectiveTests: XCTestCase {

    /// A calm, unremarkable baseline. Slight seeded wobble so MAD is non-zero
    /// and `robustZ` uses its primary path rather than an IQR/SD fallback.
    private func baseline(_ count: Int = 30, seed: UInt64 = 7) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            Fixture.night(
                daysAgo: count - index,
                timeAsleepMinutes: 450 + generator.nextDouble(in: -6...6),
                timeInBedMinutes: 500,
                avgHRV: 55 + generator.nextDouble(in: -3...3),
                restingHeartRate: 54 + generator.nextDouble(in: -1.5...1.5),
                wakeCount: 2
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Ranking

    func testRanksTheMostDeviantSignalFirst() throws {
        let history = baseline()
        // Resting HR far outside its own tight baseline; duration only mildly off.
        let night = Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 430, timeInBedMinutes: 500, restingHeartRate: 70
        )

        let report = try XCTUnwrap(
            NightDetective.investigate(night: night, history: history)
        )

        XCTAssertEqual(report.factors.first?.signal, .restingHeartRate)
        XCTAssertTrue(report.headline.contains("resting heart rate"), report.headline)
    }

    func testFactorsAreSortedByAbsoluteDeviation() throws {
        let history = baseline()
        let night = Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 250, timeInBedMinutes: 500,
            avgHRV: 20, restingHeartRate: 68, wakeCount: 11
        )

        let report = try XCTUnwrap(NightDetective.investigate(night: night, history: history))
        let magnitudes = report.factors.map { abs($0.z) }
        XCTAssertEqual(magnitudes, magnitudes.sorted(by: >))
        XCTAssertGreaterThan(report.factors.count, 1)
    }

    /// An unusually *good* night is still unusual. Ranking is by distance
    /// from baseline, not by badness.
    func testAnUnusuallyFavourableNightIsStillReported() throws {
        let history = baseline()
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 620, timeInBedMinutes: 650)

        let report = try XCTUnwrap(NightDetective.investigate(night: night, history: history))
        let duration = try XCTUnwrap(report.factors.first { $0.signal == .duration })

        XCTAssertTrue(duration.isAboveBaseline)
        XCTAssertFalse(duration.isUnfavourable, "more sleep than usual is not the bad direction")
    }

    // MARK: - Not crying wolf

    func testAnOrdinaryNightHasNoFactors() throws {
        let history = baseline()
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 450, timeInBedMinutes: 500)

        let report = try XCTUnwrap(NightDetective.investigate(night: night, history: history))
        XCTAssertTrue(report.isUnremarkable)
        XCTAssertTrue(report.headline.contains("Nothing about this night stood out"), report.headline)
    }

    func testTooLittleHistoryReturnsNil() {
        let history = baseline(10)
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 250, timeInBedMinutes: 500)
        XCTAssertNil(NightDetective.investigate(night: night, history: history))
    }

    /// The baseline must never contain the night being explained -- otherwise
    /// the most extreme nights pull their own comparison toward themselves
    /// and are the ones most understated.
    func testTheNightUnderInvestigationIsExcludedFromItsOwnBaseline() throws {
        let history = baseline()
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 250, timeInBedMinutes: 500)

        let withoutSelf = try XCTUnwrap(
            NightDetective.investigate(night: night, history: history)
        )
        let withSelf = try XCTUnwrap(
            NightDetective.investigate(night: night, history: history + [night])
        )

        let a = try XCTUnwrap(withoutSelf.factors.first { $0.signal == .duration })
        let b = try XCTUnwrap(withSelf.factors.first { $0.signal == .duration })
        XCTAssertEqual(a.z, b.z, accuracy: 0.0001,
                       "including the night in its own history must change nothing")
        XCTAssertEqual(withoutSelf.baselineNights, withSelf.baselineNights)
    }

    func testFutureNightsAreNotUsedAsBaseline() throws {
        let history = baseline()
        // A night in the middle of the record: everything after it is future.
        let subject = history[20]

        let report = try XCTUnwrap(
            NightDetective.investigate(night: subject, history: history)
        )
        XCTAssertEqual(report.baselineNights, 20, "only the 20 nights before it are eligible")
    }

    // MARK: - Missing data

    func testSignalsMissingOnTheNightAreSkipped() throws {
        let history = baseline()
        let night = Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 250, timeInBedMinutes: 500, avgHRV: nil
        )

        let report = try XCTUnwrap(NightDetective.investigate(night: night, history: history))
        XCTAssertFalse(report.factors.contains { $0.signal == .hrv })
        XCTAssertTrue(report.factors.contains { $0.signal == .duration })
    }

    func testStageSignalsAreConsideredWhenABreakdownExists() throws {
        let history = baseline()
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 250, timeInBedMinutes: 500)

        XCTAssertTrue(night.hasStageBreakdown, "precondition: the fixture derives stage minutes")
        let report = try XCTUnwrap(NightDetective.investigate(night: night, history: history))
        XCTAssertTrue(report.factors.contains { $0.signal == .deepMinutes })
    }

    /// A source that reports no stage breakdown at all must not read as a
    /// night of zero deep sleep -- that would be the largest excursion in the
    /// report, invented entirely out of missing data.
    func testStageSignalsAreSkippedWhenTheSourceReportedNoStages() throws {
        let history = baseline()
        // No time asleep at all, so the fixture derives no stage minutes --
        // the shape a source that records time in bed but not stages leaves.
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 0, timeInBedMinutes: 500)

        XCTAssertFalse(night.hasStageBreakdown, "precondition")
        let report = try XCTUnwrap(NightDetective.investigate(night: night, history: history))
        XCTAssertFalse(report.factors.contains { $0.signal == .deepMinutes })
        XCTAssertFalse(report.factors.contains { $0.signal == .remMinutes })
        XCTAssertTrue(report.factors.contains { $0.signal == .duration },
                      "duration itself is still a real, measured excursion")
    }

    // MARK: - Logged behaviours

    func testLoggedTagsAreCarriedAndHedged() throws {
        let history = baseline()
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 250, timeInBedMinutes: 500)

        let report = try XCTUnwrap(
            NightDetective.investigate(night: night, history: history, loggedTags: [.alcohol])
        )

        XCTAssertEqual(report.loggedTags, [.alcohol])
        let sentence = try XCTUnwrap(report.tagSentence)
        XCTAssertTrue(sentence.contains("alongside"), sentence)
        XCTAssertTrue(sentence.contains("not a proven cause"), sentence)
        XCTAssertFalse(sentence.lowercased().contains("because"), sentence)
        XCTAssertFalse(sentence.lowercased().contains("caused"), sentence)
    }

    func testNoTagsMeansNoTagSentence() throws {
        let history = baseline()
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 250, timeInBedMinutes: 500)

        let report = try XCTUnwrap(NightDetective.investigate(night: night, history: history))
        XCTAssertNil(report.tagSentence)
    }

    // MARK: - Copy

    func testFactorSentenceNamesTheDirectionAndBothValues() throws {
        let history = baseline()
        let night = Fixture.night(
            daysAgo: 0, timeAsleepMinutes: 450, timeInBedMinutes: 500, restingHeartRate: 70
        )

        let report = try XCTUnwrap(NightDetective.investigate(night: night, history: history))
        let factor = try XCTUnwrap(report.factors.first { $0.signal == .restingHeartRate })

        XCTAssertTrue(factor.sentence.hasPrefix("Resting heart rate"), factor.sentence)
        XCTAssertTrue(factor.sentence.contains("higher"), factor.sentence)
        XCTAssertTrue(factor.sentence.contains("70 bpm"), factor.sentence)
        XCTAssertTrue(factor.isUnfavourable, "a higher resting HR is the bad direction")
    }
}

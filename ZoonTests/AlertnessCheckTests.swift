import XCTest

/// §26 is "improve, do not rebuild", and almost all of the improvement is
/// restraint: the engine's job is to decide when six taps are allowed to mean
/// something. Most of what follows is therefore about the refusals.
final class AlertnessCheckTests: XCTestCase {

    private let morning = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func session(
        median: Double,
        minutesSinceWaking: Double? = 30,
        daysAgo: Int = 0,
        iqr: Double = 40,
        lapses: Int = 0,
        falseStarts: Int = 0
    ) -> AlertnessCheck.Session {
        AlertnessCheck.Session(
            date: morning.addingTimeInterval(Double(-daysAgo) * 86_400),
            medianMilliseconds: median,
            iqrMilliseconds: iqr,
            lapses: lapses,
            falseStarts: falseStarts,
            trials: 6,
            minutesSinceWaking: minutesSinceWaking
        )
    }

    /// `count` prior sessions, oldest first, all at the same point after
    /// waking unless told otherwise.
    private func history(_ count: Int, median: Double = 300, minutesSinceWaking: Double? = 30)
        -> [AlertnessCheck.Session] {
        guard count > 0 else { return [] }
        return (1...count).reversed().map {
            session(median: median, minutesSinceWaking: minutesSinceWaking, daysAgo: $0)
        }
    }

    // MARK: - Building a session

    func testASessionCarriesTheSpreadAsWellAsTheMedian() throws {
        let reactions = [0.24, 0.26, 0.30, 0.32, 0.40, 0.52]
        let session = try XCTUnwrap(
            AlertnessCheck.session(reactions: reactions, date: morning)
        )
        XCTAssertEqual(session.medianMilliseconds, 310, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(session.iqrMilliseconds), 110, accuracy: 0.001)
        XCTAssertEqual(session.trials, 6)
    }

    /// The same median, two different states. A steady responder and somebody
    /// alternating between fast and gone are not the same, and the median
    /// alone cannot tell them apart — which is why the brief asks for the IQR.
    func testTwoRunsWithTheSameMedianAreSeparatedByTheirSpread() throws {
        let steady = try XCTUnwrap(
            AlertnessCheck.session(reactions: [0.29, 0.30, 0.30, 0.31, 0.31, 0.32], date: morning)
        )
        let ragged = try XCTUnwrap(
            AlertnessCheck.session(reactions: [0.20, 0.22, 0.30, 0.31, 0.48, 0.60], date: morning)
        )
        XCTAssertEqual(steady.medianMilliseconds, ragged.medianMilliseconds, accuracy: 10)
        XCTAssertGreaterThan(
            try XCTUnwrap(ragged.iqrMilliseconds), try XCTUnwrap(steady.iqrMilliseconds) * 5
        )
    }

    func testAResponseOverHalfASecondIsALapse() throws {
        let session = try XCTUnwrap(
            AlertnessCheck.session(reactions: [0.28, 0.30, 0.52, 0.31, 0.80, 0.29], date: morning)
        )
        XCTAssertEqual(session.lapses, 2)
    }

    /// The brief asks for false starts. The old store discarded them, so a run
    /// of taps before the signal left no trace at all.
    func testFalseStartsAreKeptRatherThanDiscarded() throws {
        let session = try XCTUnwrap(
            AlertnessCheck.session(
                reactions: [0.28, 0.30, 0.31, 0.29, 0.30, 0.32], falseStarts: 3, date: morning
            )
        )
        XCTAssertEqual(session.falseStarts, 3)
        XCTAssertEqual(
            AlertnessCheck.falseStartNote(3),
            "3 taps before the signal. These are not in the median."
        )
    }

    func testNoFalseStartsMeansNoLineAboutThem() {
        XCTAssertNil(AlertnessCheck.falseStartNote(0))
    }

    func testTooFewTrialsIsNotASession() {
        XCTAssertNil(AlertnessCheck.session(reactions: [0.3, 0.3, 0.3, 0.3], date: morning))
    }

    // MARK: - Time since waking

    func testTimeSinceWakingIsRecordedWhenTheNightIsKnown() throws {
        let session = try XCTUnwrap(
            AlertnessCheck.session(
                reactions: Array(repeating: 0.3, count: 6),
                wakeTime: morning.addingTimeInterval(-45 * 60),
                date: morning
            )
        )
        XCTAssertEqual(try XCTUnwrap(session.minutesSinceWaking), 45, accuracy: 0.001)
    }

    /// A wake time from three nights ago, because nothing has been recorded
    /// since, would produce a figure that looks like data.
    func testAStaleWakeTimeIsRefusedRatherThanRecorded() throws {
        let session = try XCTUnwrap(
            AlertnessCheck.session(
                reactions: Array(repeating: 0.3, count: 6),
                wakeTime: morning.addingTimeInterval(-3 * 86_400),
                date: morning
            )
        )
        XCTAssertNil(session.minutesSinceWaking)
    }

    func testNoWakeTimeIsLeftAbsentRatherThanZero() throws {
        let session = try XCTUnwrap(
            AlertnessCheck.session(reactions: Array(repeating: 0.3, count: 6), date: morning)
        )
        XCTAssertNil(session.minutesSinceWaking)
    }

    // MARK: - Practice

    /// The trap the whole engine exists for: reaction time falls over the
    /// first few attempts because the task is being learned. Reporting that as
    /// an improvement would be the app measuring itself.
    func testTheFirstSessionsAreTreatedAsLearningTheTask() {
        for completed in 1..<AlertnessCheck.practiceSessions {
            let latest = session(median: 400, daysAgo: 0)
            let outcome = AlertnessCheck.evaluate(
                latest: latest, history: history(completed - 1) + [latest]
            )
            guard case .withheld(.practice(let remaining)) = outcome else {
                return XCTFail("expected practice, got \(outcome)")
            }
            XCTAssertEqual(remaining, AlertnessCheck.practiceSessions - completed)
        }
    }

    /// A dramatic improvement across the practice window is still withheld.
    /// This is the exact case an app would be tempted to celebrate.
    func testALargeImprovementDuringPracticeIsStillNotReported() {
        let latest = session(median: 260, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(
            latest: latest,
            history: [session(median: 420, daysAgo: 2), latest]
        )
        guard case .withheld(.practice) = outcome else {
            return XCTFail("expected practice, got \(outcome)")
        }
        XCTAssertFalse(outcome.sentence.lowercased().contains("faster"), outcome.sentence)
        XCTAssertTrue(outcome.sentence.contains("learn the task"), outcome.sentence)
    }

    func testPracticeSessionsAreExcludedFromTheBaselineTheyPrecede() {
        // Three very slow practice sessions, then five steady ones. The
        // baseline must be the steady ones alone, so a latest at 300 reads as
        // the same rather than as a large improvement.
        let practice = (9...11).reversed().map { session(median: 600, daysAgo: $0) }
        let steady = (1...5).reversed().map { session(median: 300, daysAgo: $0) }
        let latest = session(median: 300, daysAgo: 0)

        let outcome = AlertnessCheck.evaluate(
            latest: latest, history: practice + steady + [latest]
        )
        let comparison = outcome.comparison
        XCTAssertEqual(comparison?.baselineMedian, 300)
        XCTAssertEqual(comparison?.baselineSessions, 5)
        XCTAssertTrue(outcome.sentence.contains("About the same"), outcome.sentence)
    }

    // MARK: - Withholding until there is a baseline

    func testNoComparisonUntilEnoughSessionsExistAfterPractice() {
        let latest = session(median: 300, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(
            latest: latest, history: history(5) + [latest]
        )
        guard case .withheld(.buildingBaseline(let remaining)) = outcome else {
            return XCTFail("expected buildingBaseline, got \(outcome)")
        }
        XCTAssertEqual(remaining, 3)
        XCTAssertNil(outcome.comparison)
    }

    func testTheFirstComparisonArrivesOnceThereIsABaseline() throws {
        let latest = session(median: 300, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(
            latest: latest, history: history(8) + [latest]
        )
        let comparison = try XCTUnwrap(outcome.comparison)
        XCTAssertEqual(comparison.baselineSessions, 5)
        XCTAssertEqual(comparison.confidence, .moderate)
    }

    // MARK: - Like with like

    /// Sleep inertia alone moves reaction time more than most of what this is
    /// looking for, so a check twenty minutes after waking and one six hours
    /// later are not the same quantity.
    func testACheckAtADifferentPointAfterWakingHasNothingToCompareAgainst() {
        let latest = session(median: 300, minutesSinceWaking: 400, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(
            latest: latest,
            history: history(10, minutesSinceWaking: 30) + [latest]
        )
        guard case .withheld(.noComparableTimeOfMorning) = outcome else {
            return XCTFail("expected noComparableTimeOfMorning, got \(outcome)")
        }
    }

    func testAModestDifferenceInTimeOfMorningStillCompares() {
        let latest = session(median: 300, minutesSinceWaking: 100, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(
            latest: latest,
            history: history(10, minutesSinceWaking: 30) + [latest]
        )
        XCTAssertNotNil(outcome.comparison)
    }

    /// Two checks with no wake time either side are still like with like:
    /// both are simply "a check", and the tolerance cannot be applied to a
    /// number nobody has.
    func testSessionsWithNoWakeTimeCompareAgainstEachOther() {
        let latest = session(median: 300, minutesSinceWaking: nil, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(
            latest: latest,
            history: history(10, minutesSinceWaking: nil) + [latest]
        )
        XCTAssertNotNil(outcome.comparison)
    }

    func testAKnownWakeTimeIsNotComparedAgainstSessionsThatHaveNone() {
        let latest = session(median: 300, minutesSinceWaking: 30, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(
            latest: latest,
            history: history(10, minutesSinceWaking: nil) + [latest]
        )
        guard case .withheld(.noComparableTimeOfMorning) = outcome else {
            return XCTFail("expected noComparableTimeOfMorning, got \(outcome)")
        }
    }

    // MARK: - What a comparison says

    func testASmallDifferenceIsReportedAsNoDifference() throws {
        let latest = session(median: 320, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(latest: latest, history: history(10) + [latest])
        XCTAssertTrue(outcome.sentence.contains("About the same"), outcome.sentence)
        XCTAssertEqual(try XCTUnwrap(outcome.comparison).differenceMilliseconds, 20, accuracy: 0.001)
    }

    func testASlowerCheckIsNamedAsSlowerThanYourOwnRecentChecks() {
        let latest = session(median: 400, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(latest: latest, history: history(10) + [latest])
        XCTAssertTrue(outcome.sentence.contains("100 ms slower"), outcome.sentence)
        XCTAssertTrue(outcome.sentence.contains("your own recent checks"), outcome.sentence)
    }

    func testAFasterCheckIsNamedWithoutBeingCelebrated() {
        let latest = session(median: 220, daysAgo: 0)
        let outcome = AlertnessCheck.evaluate(latest: latest, history: history(10) + [latest])
        XCTAssertTrue(outcome.sentence.contains("80 ms faster"), outcome.sentence)
    }

    func testConfidenceRisesWithTheSizeOfTheBaseline() throws {
        let latest = session(median: 300, daysAgo: 0)
        let small = AlertnessCheck.evaluate(latest: latest, history: history(8) + [latest])
        let large = AlertnessCheck.evaluate(latest: latest, history: history(20) + [latest])
        XCTAssertEqual(try XCTUnwrap(small.comparison).confidence, .moderate)
        XCTAssertEqual(try XCTUnwrap(large.comparison).confidence, .high)
    }

    // MARK: - What it must never say

    /// A lapse threshold borrowed from a ten-minute task, printed against six
    /// taps, borrows an authority this check does not have.
    func testTheLapseCountCarriesTheCaveatAboutWhereItsThresholdComesFrom() {
        XCTAssertTrue(AlertnessCheck.lapseCaveat.contains("ten-minute task"))
        XCTAssertTrue(AlertnessCheck.lapseCaveat.contains("six taps"))
    }

    func testNothingTheEngineSaysAssessesThePerson() {
        let latest = session(median: 520, daysAgo: 0, lapses: 3)
        let outcomes: [AlertnessCheck.Outcome] = [
            AlertnessCheck.evaluate(latest: latest, history: [latest]),
            AlertnessCheck.evaluate(latest: latest, history: history(5) + [latest]),
            AlertnessCheck.evaluate(latest: latest, history: history(10) + [latest]),
            AlertnessCheck.evaluate(
                latest: session(median: 300, minutesSinceWaking: 500, daysAgo: 0),
                history: history(10) + [latest]
            )
        ]
        var lines = outcomes.map { $0.sentence }
        lines.append(AlertnessCheck.lapseCaveat)
        lines.append(AlertnessCheck.falseStartNote(2) ?? "")

        for line in lines {
            XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(line), line)
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(line), line)
            for banned in AlertnessCheck.bannedClaims {
                XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
            }
        }
    }

    // MARK: - Storage

    func testASessionSurvivesARoundTripThroughJSON() throws {
        let original = session(median: 310, iqr: 95, lapses: 1, falseStarts: 2)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AlertnessCheck.Session.self, from: data), original)
    }
}

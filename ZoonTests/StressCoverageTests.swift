import XCTest

/// §12. A Physiological Load score resting on forty minutes of a twelve-hour
/// day read exactly like one resting on seven hours. `sampledMinutes` was
/// carried on the model and spent on nothing.
///
/// The audit asks for this to come from observed coverage rather than from
/// the hardware's name, and none of what follows consults a device model.
final class StressCoverageTests: XCTestCase {

    private func score(
        sampled: Double,
        elapsed: Double?,
        hr: Double? = 70,
        hrBaseline: Double? = 62
    ) -> StressScore? {
        StressScore.compute(
            avgHeartRate: hr,
            avgHRV: nil,
            hrBaseline: hrBaseline,
            hrvBaseline: nil,
            sampledMinutes: sampled,
            baselineNightCount: 10,
            elapsedWakingMinutes: elapsed
        )
    }

    // MARK: - Coverage is a ratio of the day

    func testCoverageIsSampledOverElapsed() throws {
        let subject = try XCTUnwrap(score(sampled: 300, elapsed: 600))
        XCTAssertEqual(try XCTUnwrap(subject.quietCoverage), 0.5, accuracy: 0.001)
    }

    func testCoverageCannotExceedTheWholeDay() throws {
        let subject = try XCTUnwrap(score(sampled: 900, elapsed: 600))
        XCTAssertEqual(try XCTUnwrap(subject.quietCoverage), 1.0, accuracy: 0.001)
    }

    /// A caller that does not know how long the day has been gets no coverage
    /// judgement, rather than a guessed one.
    func testAnUnknownDayLengthYieldsNoCoverageJudgement() throws {
        let subject = try XCTUnwrap(score(sampled: 300, elapsed: nil))
        XCTAssertNil(subject.quietCoverage)
        XCTAssertNil(subject.coverageConfidence)
        XCTAssertNil(subject.coverageNote)
    }

    func testAZeroLengthDayIsNotDividedBy() throws {
        let subject = try XCTUnwrap(score(sampled: 0, elapsed: 0))
        XCTAssertNil(subject.quietCoverage)
    }

    // MARK: - The morning artefact

    /// The failure a ratio alone walks into. An hour after waking, a
    /// completely quiet hour is 100% coverage — of a one-hour day. Reporting
    /// that as high confidence would be an artefact of the clock, not a
    /// property of the data.
    func testAQuietFirstHourIsNotHighConfidence() throws {
        let subject = try XCTUnwrap(score(sampled: 60, elapsed: 60))
        XCTAssertEqual(try XCTUnwrap(subject.quietCoverage), 1.0, accuracy: 0.001)
        XCTAssertNotEqual(subject.coverageConfidence, .high)
    }

    /// The same share of a full day is a different thing entirely.
    func testTheSameShareOfAFullDayIsHighConfidence() throws {
        let subject = try XCTUnwrap(score(sampled: 420, elapsed: 720))
        XCTAssertEqual(subject.coverageConfidence, .high)
    }

    // MARK: - A busy day rests on less

    /// Twelve hours awake, forty minutes of it quiet: the reading is real but
    /// it is standing on very little, and must not present as though it were
    /// standing on the day.
    func testAMostlyActiveDayReadsAsLowCoverage() throws {
        let busy = try XCTUnwrap(score(sampled: 40, elapsed: 720))
        XCTAssertEqual(busy.coverageConfidence, .low)

        let quiet = try XCTUnwrap(score(sampled: 420, elapsed: 720))
        XCTAssertGreaterThan(
            try XCTUnwrap(quiet.coverageConfidence),
            try XCTUnwrap(busy.coverageConfidence)
        )
    }

    func testAlmostNoQuietTimeIsReportedAsInsufficient() throws {
        let subject = try XCTUnwrap(score(sampled: 12, elapsed: 720))
        XCTAssertEqual(subject.coverageConfidence, .insufficient)
    }

    /// The note has to say what it rests on, in terms somebody reads.
    func testTheNoteNamesTheAmountAndTheShare() throws {
        let subject = try XCTUnwrap(score(sampled: 420, elapsed: 720))
        let note = try XCTUnwrap(subject.coverageNote)
        XCTAssertTrue(note.contains("7.0 hours"), note)
        XCTAssertTrue(note.contains("58%"), note)
    }

    func testAThinNoteSaysTheDayWasTooActive() throws {
        let subject = try XCTUnwrap(score(sampled: 40, elapsed: 720))
        let note = try XCTUnwrap(subject.coverageNote)
        XCTAssertTrue(note.contains("too active"), note)
    }

    // MARK: - No hardware favouritism

    /// Nothing here consults a device model, and the same inputs produce the
    /// same answer whatever produced them. Stated as a test because the
    /// audit's instruction is specifically not to hard-code that newer
    /// hardware is better.
    func testCoverageDependsOnlyOnTheDayNotOnWhatMeasuredIt() throws {
        let first = try XCTUnwrap(score(sampled: 300, elapsed: 600))
        let second = try XCTUnwrap(score(sampled: 300, elapsed: 600))
        XCTAssertEqual(first.coverageConfidence, second.coverageConfidence)
        XCTAssertEqual(first.quietCoverage, second.quietCoverage)
    }

    /// Denser hardware benefits only where it genuinely yields more usable
    /// quiet time — which is the same rule that applies to a calmer day on
    /// older hardware.
    func testMoreUsableQuietTimeEarnsMoreConfidenceWhoeverProducedIt() throws {
        let sparse = try XCTUnwrap(score(sampled: 95, elapsed: 600))
        let dense = try XCTUnwrap(score(sampled: 400, elapsed: 600))
        XCTAssertGreaterThan(
            try XCTUnwrap(dense.coverageConfidence),
            try XCTUnwrap(sparse.coverageConfidence)
        )
    }

    // MARK: - Backward compatibility

    /// A record written before coverage existed decodes without it, and
    /// claims nothing.
    func testAStoredScoreWithoutCoverageDecodesAndClaimsNothing() throws {
        let subject = try XCTUnwrap(score(sampled: 300, elapsed: 600))
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(subject)
        ) as! [String: Any]
        json.removeValue(forKey: "elapsedWakingMinutes")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(StressScore.self, from: data)
        XCTAssertNil(decoded.elapsedWakingMinutes)
        XCTAssertNil(decoded.coverageConfidence)
    }
}

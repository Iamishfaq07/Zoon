import XCTest

final class ModelHealthTests: XCTestCase {

    private func assess(
        nights: Int = 40,
        recovery: Int? = nil,
        bodySignals: Int? = nil,
        coverage: Double? = 0.9,
        claims: Int = 4,
        calibration: CalibrationLedger.Verdict? = .matchesExpectation,
        pairs: Int? = 20
    ) -> [ModelHealth.Assessment] {
        ModelHealth.assess(
            nightCount: nights,
            nightsWithRecoverySignal: recovery ?? nights,
            nightsWithBodySignals: bodySignals ?? nights,
            coverage: coverage,
            settledClaims: claims,
            calibration: calibration,
            matchedPairs: pairs
        )
    }

    private func stage(_ area: ModelHealth.Area, in assessments: [ModelHealth.Assessment]) -> ModelHealth.Stage? {
        assessments.first { $0.area == area }?.stage
    }

    // MARK: - Not a score

    /// The rule the spec states twice. Nothing this type produces may be a
    /// number out of a hundred, and nothing it says may read as one.
    func testNothingHereIsANumberOutOfAHundred() {
        for assessment in assess() {
            XCTAssertFalse(assessment.stage.label.contains("%"), "\(assessment.area.rawValue)")
            XCTAssertFalse(assessment.area.label.lowercased().contains("score"))
        }
        for stage in ModelHealth.Stage.allCases {
            XCTAssertFalse(stage.label.contains("/"))
            XCTAssertFalse(stage.label.rangeOfCharacter(from: .decimalDigits) != nil,
                           "\(stage) reads as a number")
        }
    }

    /// Averaging stages is a score with the numbers hidden, and it says the
    /// wrong thing: a model with a hole in it is not "moderately
    /// personalised", it is a model with a hole.
    func testTheOverallStageIsTheWeakestAreaAndNotTheAverage() {
        let assessments = assess(nights: 120, claims: 12, pairs: 40, coverage: 0.99)
        XCTAssertEqual(ModelHealth.overall(assessments), .wellEstablished,
                       "fixture must top out, or the next assertion proves nothing")

        // One thin area, everything else unchanged.
        let holed = assess(nights: 120, recovery: 3, claims: 12, pairs: 40, coverage: 0.99)
        XCTAssertEqual(ModelHealth.overall(holed), .learning)
        XCTAssertTrue(ModelHealth.headline(holed).contains("recovery baseline"))
    }

    func testTheHeadlineSaysSoWhenEverythingIsAtTheSamePoint() {
        let flat = assess(nights: 4, recovery: 4, bodySignals: 4, coverage: nil, claims: 0,
                          calibration: nil, pairs: nil)
        XCTAssertEqual(ModelHealth.overall(flat), .learning)
        XCTAssertTrue(ModelHealth.headline(flat).contains("same point"))
    }

    // MARK: - Reading each area

    func testAThinHistoryIsStillLearningEverywhere() {
        let early = assess(nights: 5, coverage: nil, claims: 0, calibration: nil, pairs: nil)
        XCTAssertTrue(early.allSatisfy { $0.stage == .learning }, "\(early)")
        XCTAssertEqual(early.count, ModelHealth.Area.allCases.count)
    }

    /// A baseline cannot be built from a night that carried no reading, and
    /// quoting the night count would overstate exactly the areas with the
    /// least behind them.
    func testABaselineIsGradedOnTheNightsThatCarriedAReadingNotOnEveryNight() {
        let assessments = assess(nights: 90, recovery: 10)
        XCTAssertEqual(stage(.sleepNeed, in: assessments), .wellEstablished)
        XCTAssertEqual(stage(.recoveryBaseline, in: assessments), .learning)
        XCTAssertTrue(
            assessments.first { $0.area == .recoveryBaseline }?.basis.contains("10 nights") ?? false
        )
    }

    /// Thin data caps the reading however many nights there are: a long
    /// history of nights that carried almost nothing is a long history of
    /// almost nothing.
    func testThinCoverageCapsTheReadingHoweverManyNightsThereAre() {
        XCTAssertEqual(stage(.dataCoverage, in: assess(nights: 200, coverage: 0.3)), .learning)
        XCTAssertEqual(stage(.dataCoverage, in: assess(nights: 200, coverage: 0.99)), .wellEstablished)
        // And the reverse: perfect coverage over four nights is four nights.
        XCTAssertEqual(stage(.dataCoverage, in: assess(nights: 4, coverage: 1.0)), .learning)
    }

    /// "Your ranges are narrower than they should be" is a finding that the
    /// ranges are wrong. Ranking it alongside ranges that hold up would let a
    /// model be called personalised for knowing it is miscalibrated.
    func testKnowingItsRangesAreWrongDoesNotCountAsKnowingYouWell() {
        XCTAssertEqual(stage(.forecast, in: assess(calibration: .matchesExpectation)), .wellEstablished)
        for wrong in [CalibrationLedger.Verdict.tooConfident, .tooCautious] {
            XCTAssertEqual(stage(.forecast, in: assess(calibration: wrong)), .establishing, "\(wrong)")
        }
        XCTAssertEqual(stage(.forecast, in: assess(calibration: .notEnoughYet)), .learning)
        XCTAssertEqual(stage(.forecast, in: assess(calibration: nil)), .learning)
    }

    func testNoSupportedComparisonReadsAsStillLearningRatherThanAsAFailure() {
        let assessments = assess(pairs: nil)
        XCTAssertEqual(stage(.matchedComparisons, in: assessments), .learning)
        let basis = assessments.first { $0.area == .matchedComparisons }?.basis ?? ""
        XCTAssertFalse(basis.lowercased().contains("fail"))
        XCTAssertFalse(basis.isEmpty)
    }

    // MARK: - Every area says something

    /// A stage with no basis is a grade. Every reading has to carry what it
    /// was read off.
    func testEveryAssessmentCarriesWhatItWasReadOff() {
        for assessment in assess() + assess(nights: 3, coverage: nil, claims: 0, calibration: nil, pairs: nil) {
            XCTAssertFalse(assessment.basis.isEmpty, "\(assessment.area.rawValue) has no basis")
            XCTAssertFalse(assessment.area.question.isEmpty)
            XCTAssertFalse(assessment.stage.meaning.isEmpty)
        }
    }

    func testTheLadderIsMonotonic() {
        var seen: [ModelHealth.Stage] = []
        for count in 0...80 {
            let stage = ModelHealth.stage(
                for: count,
                establishing: ModelHealth.establishingNights,
                personalised: ModelHealth.personalisedNights,
                wellEstablished: ModelHealth.wellEstablishedNights
            )
            if let last = seen.last {
                XCTAssertGreaterThanOrEqual(stage, last, "the ladder went backwards at \(count)")
            }
            seen.append(stage)
        }
        XCTAssertEqual(seen.first, .learning)
        XCTAssertEqual(seen.last, .wellEstablished)
        XCTAssertEqual(Set(seen).count, 4, "every step must be reachable")
    }
}

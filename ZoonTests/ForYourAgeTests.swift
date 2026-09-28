import XCTest

/// Age, sex and heart rate have to change what Zoon says, and change it
/// correctly: the sleep range by age, the heart context by age and sex, and
/// the overnight heart summary.
final class ForYourAgeTests: XCTestCase {

    // MARK: - Sleep need by age (National Sleep Foundation)

    func testEachAgeGetsItsOwnRecommendation() {
        XCTAssertEqual(SleepNeedGuideline.forAge(16)?.recommendedText, "8–10 hours")
        XCTAssertEqual(SleepNeedGuideline.forAge(18)?.recommendedText, "7–9 hours")
        XCTAssertEqual(SleepNeedGuideline.forAge(34)?.recommendedText, "7–9 hours")
        XCTAssertEqual(SleepNeedGuideline.forAge(64)?.recommendedText, "7–9 hours")
        XCTAssertEqual(SleepNeedGuideline.forAge(65)?.recommendedText, "7–8 hours")
        XCTAssertEqual(SleepNeedGuideline.forAge(90)?.recommendedText, "7–8 hours")
    }

    func testNoAgeMeansNoRecommendation() {
        XCTAssertNil(SleepNeedGuideline.forAge(nil))
        XCTAssertNil(SleepNeedGuideline.forAge(2))
    }

    /// The starting goal is the middle of the range, so a teenager starts at
    /// nine hours and someone over 65 at seven and a half, not everyone at 8.
    func testTheStartingGoalFollowsAge() {
        XCTAssertEqual(SleepNeedGuideline.forAge(16)?.suggestedGoalMinutes, 540)
        XCTAssertEqual(SleepNeedGuideline.forAge(34)?.suggestedGoalMinutes, 480)
        XCTAssertEqual(SleepNeedGuideline.forAge(70)?.suggestedGoalMinutes, 450)
    }

    func testAGoalIsPlacedAgainstTheRangeForItsAge() throws {
        let adult = try XCTUnwrap(SleepNeedGuideline.forAge(40))
        XCTAssertEqual(adult.fit(480), .withinRecommended)
        XCTAssertEqual(adult.fit(390), .belowRecommended)
        XCTAssertEqual(adult.fit(330), .wellBelow)
        XCTAssertEqual(adult.fit(570), .aboveRecommended)
        XCTAssertEqual(adult.fit(630), .wellAbove)

        // Eight and a half hours is inside the adult range and over the
        // range for someone past 65: age changes the answer.
        let older = try XCTUnwrap(SleepNeedGuideline.forAge(70))
        XCTAssertEqual(adult.fit(510), .withinRecommended)
        XCTAssertEqual(older.fit(510), .aboveRecommended)
    }

    func testTheGoalSentenceNamesTheGroupAndTheRange() throws {
        let teen = try XCTUnwrap(SleepNeedGuideline.forAge(16))
        let sentence = teen.goalSentence(goalMinutes: 420)
        XCTAssertTrue(sentence.contains("8–10 hours"), sentence)
        XCTAssertTrue(sentence.contains("teenagers"), sentence)
        XCTAssertTrue(sentence.contains("under"), sentence)
    }

    // MARK: - Resting heart rate

    func testRestingHeartRateIsPlacedAgainstTheUsualAdultRange() {
        XCTAssertEqual(HeartContext.restingHeartRate(38, sex: .male).position, .below)
        XCTAssertEqual(HeartContext.restingHeartRate(52, sex: .male).position, .below)
        XCTAssertEqual(HeartContext.restingHeartRate(64, sex: .female).position, .typical)
        XCTAssertEqual(HeartContext.restingHeartRate(100, sex: .female).position, .typical)
        XCTAssertEqual(HeartContext.restingHeartRate(104, sex: .female).position, .above)
    }

    func testSexChangesTheRestingSentence() {
        let female = HeartContext.restingHeartRate(66, sex: .female).sentence
        let male = HeartContext.restingHeartRate(66, sex: .male).sentence
        let unset = HeartContext.restingHeartRate(66, sex: .unspecified).sentence
        XCTAssertTrue(female.contains("Women's"), female)
        XCTAssertTrue(male.contains("Men's"), male)
        XCTAssertFalse(unset.contains("Women's") || unset.contains("Men's"), unset)
    }

    // MARK: - HRV by age

    /// Voss et al. 2015: about 50 ms at 25–34 falling to about 30 ms at
    /// 65–74.
    func testTypicalHRVFallsWithAge() {
        XCTAssertEqual(HeartContext.typicalHRV(age: 25), 50)
        XCTAssertEqual(HeartContext.typicalHRV(age: 30), 50)
        XCTAssertEqual(HeartContext.typicalHRV(age: 50), 40)
        XCTAssertEqual(HeartContext.typicalHRV(age: 70), 30)
        XCTAssertEqual(HeartContext.typicalHRV(age: 88), 28, "held flat past the studied range")
    }

    /// The same 32 ms is below typical at 25 and typical at 68.
    func testTheSameHRVReadsDifferentlyAtDifferentAges() {
        XCTAssertEqual(HeartContext.heartRateVariability(32, age: 25).position, .below)
        XCTAssertEqual(HeartContext.heartRateVariability(32, age: 68).position, .typical)
        XCTAssertEqual(HeartContext.heartRateVariability(80, age: 40).position, .above)
    }

    // MARK: - Cardio fitness by age and sex (FRIEND 2015)

    func testCardioFitnessMediansDependOnAgeAndSex() {
        XCTAssertEqual(HeartContext.typicalVO2Max(age: 25, sex: .male), 48.0)
        XCTAssertEqual(HeartContext.typicalVO2Max(age: 34, sex: .male), 42.4)
        XCTAssertEqual(HeartContext.typicalVO2Max(age: 34, sex: .female), 30.9)
        XCTAssertEqual(HeartContext.typicalVO2Max(age: 79, sex: .female), 20.8)
    }

    func testCardioFitnessNeedsASexAndAnAgeInTheRegistry() {
        XCTAssertNil(HeartContext.typicalVO2Max(age: 34, sex: .unspecified))
        XCTAssertNil(HeartContext.typicalVO2Max(age: 19, sex: .male))
        XCTAssertNil(HeartContext.typicalVO2Max(age: 80, sex: .male))
        XCTAssertNil(HeartContext.cardioFitness(40, age: 34, sex: .unspecified))
    }

    /// 36 is below the middle for a man of 34 and above it for a woman of
    /// the same age.
    func testTheSameCardioFitnessReadsDifferentlyBySex() throws {
        let man = try XCTUnwrap(HeartContext.cardioFitness(36, age: 34, sex: .male))
        let woman = try XCTUnwrap(HeartContext.cardioFitness(36, age: 34, sex: .female))
        XCTAssertEqual(man.position, .below)
        XCTAssertEqual(woman.position, .above)
        XCTAssertTrue(man.sentence.contains("men aged 30–39"), man.sentence)
        XCTAssertTrue(woman.sentence.contains("women aged 30–39"), woman.sentence)
    }

    // MARK: - Heart during sleep

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func night(hours: Double = 8, lowAt fraction: Double) -> (samples: [(date: Date, bpm: Double)], interval: DateInterval) {
        let interval = DateInterval(start: start, duration: hours * 3600)
        let steps = Int(hours * 12)
        let samples = (0..<steps).map { index -> (date: Date, bpm: Double) in
            let position = Double(index) / Double(steps)
            // A V with its point at `fraction`: 50 bpm at the low, rising to
            // 50 + 20 at the far ends.
            let bpm = 50 + 20 * abs(position - fraction)
            return (start.addingTimeInterval(Double(index) * 300), bpm)
        }
        return (samples, interval)
    }

    func testAnEarlyLowIsSaidToBeEarly() throws {
        let data = night(lowAt: 0.3)
        let summary = try XCTUnwrap(OvernightHeartSummary.make(
            samples: data.samples, night: data.interval, restingHeartRate: 62
        ))
        XCTAssertEqual(summary.timing, .early)
        XCTAssertEqual(summary.lowestFraction, 0.3, accuracy: 0.03)
        let sentence = summary.timingSentence(clock: { _ in "1:00 AM" })
        XCTAssertTrue(sentence.contains("first half"), sentence)
    }

    func testALowNearWakingIsSaidToBeLate() throws {
        let data = night(lowAt: 0.9)
        let summary = try XCTUnwrap(OvernightHeartSummary.make(
            samples: data.samples, night: data.interval, restingHeartRate: nil
        ))
        XCTAssertEqual(summary.timing, .late)
        XCTAssertTrue(summary.timingSentence(clock: { _ in "6:00 AM" }).contains("close to waking"))
        XCTAssertNil(summary.restingSentence, "no resting rate, no comparison")
    }

    /// One low five-minute bin is noise; the lowest point is a 15-minute
    /// average, so a single spike cannot move it across the night.
    func testASingleNoisyReadingDoesNotDecideTheLowestPoint() throws {
        var data = night(lowAt: 0.3)
        let spikeIndex = Int(Double(data.samples.count) * 0.95)
        data.samples[spikeIndex].bpm = 40
        let summary = try XCTUnwrap(OvernightHeartSummary.make(
            samples: data.samples, night: data.interval, restingHeartRate: nil
        ))
        XCTAssertEqual(summary.timing, .early)
    }

    func testTheSleepingAverageIsComparedWithTheRestingRate() throws {
        let data = night(lowAt: 0.4)
        let summary = try XCTUnwrap(OvernightHeartSummary.make(
            samples: data.samples, night: data.interval, restingHeartRate: 70
        ))
        let percent = try XCTUnwrap(summary.belowRestingPercent)
        XCTAssertGreaterThan(percent, 0)
        XCTAssertTrue(summary.restingSentence?.contains("below your daytime resting rate of 70 bpm") == true)
    }

    /// Apple's resting rate is not a sleeping rate, so a small gap is ordinary
    /// and must not read as strain.
    func testASmallGapFromTheRestingRateIsOrdinary() throws {
        let data = night(lowAt: 0.4)
        let summary = try XCTUnwrap(OvernightHeartSummary.make(
            samples: data.samples, night: data.interval, restingHeartRate: 53
        ))
        let sentence = try XCTUnwrap(summary.restingSentence)
        XCTAssertTrue(sentence.contains("ordinary"), sentence)
        XCTAssertFalse(sentence.contains("strain"), sentence)
    }

    func testTooFewReadingsGiveNoSummary() {
        let interval = DateInterval(start: start, duration: 8 * 3600)
        let samples: [(date: Date, bpm: Double)] = (0..<4).map {
            (date: start.addingTimeInterval(Double($0) * 3600), bpm: 55.0)
        }
        XCTAssertNil(OvernightHeartSummary.make(samples: samples, night: interval, restingHeartRate: 60))
    }

    // MARK: - Glossary

    func testEveryGlossaryTermIsNamedOnceAndHasASymbol() {
        let names = SleepVocabulary.all.map(\.plain)
        XCTAssertEqual(names.count, Set(names).count, "a plain name is listed twice")
        for term in SleepVocabulary.all {
            XCTAssertFalse(term.symbol.isEmpty, "\(term.plain) has no symbol")
        }
        XCTAssertGreaterThanOrEqual(SleepVocabulary.all.count, 20)
    }
}

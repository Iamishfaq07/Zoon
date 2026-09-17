import XCTest

/// §9. "Had two coffees, last one around 5" and "coffee" used to be the same
/// stored row. The parser already read the hour out of that sentence and spent
/// it on a display string nothing could query.
///
/// The risk in fixing it is the opposite of the bug: a parser that helpfully
/// fills in a quantity nobody stated poisons every curve built on it, and does
/// so invisibly. Most of what follows is about what is *not* extracted.
final class BehaviorDetailTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Tuesday 15 September 2026, the morning a night is filed under.
    private var nightDay: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 15
        return calendar.date(from: components)!
    }

    private func proposal(_ text: String, tag: BehaviorTag) -> NaturalJournalParser.Proposal? {
        NaturalJournalParser.proposals(from: text).first { $0.tag == tag }
    }

    // MARK: - Reading the sentence

    /// The brief's own example, and the honest reading of it.
    ///
    /// "Two" is a fact: the sentence says it. "Around 5" is not — it means
    /// five in the afternoon to everybody who writes it, and nothing in the
    /// sentence says so. Zoon keeps the count and declines the hour rather
    /// than storing a guess, because a guess written into a dose curve is
    /// indistinguishable from a measurement once it is there. The person adds
    /// the time at confirmation if they want it.
    func testTwoCoffeesLastOneAroundFiveKeepsTheCountAndNotTheGuess() throws {
        let caffeine = try XCTUnwrap(
            proposal("Had two coffees, last one around 5", tag: .caffeine)
        )
        XCTAssertEqual(caffeine.quantity, 2)
        XCTAssertNil(caffeine.eventClockMinutes, "an ambiguous hour was resolved rather than refused")
    }

    /// Said plainly, it is kept.
    func testTheSameSentenceWithAMeridiemKeepsTheHour() throws {
        let caffeine = try XCTUnwrap(
            proposal("Had two coffees, last one around 5 pm", tag: .caffeineLate)
        )
        XCTAssertEqual(caffeine.quantity, 2)
        XCTAssertEqual(caffeine.eventClockMinutes, 17 * 60)
    }

    /// An hour past noon can only mean one thing, so no meridiem is needed.
    func testATwentyFourHourClockNeedsNoMeridiem() throws {
        let caffeine = try XCTUnwrap(proposal("coffee at 17", tag: .caffeineLate))
        XCTAssertEqual(caffeine.eventClockMinutes, 17 * 60)
    }

    func testDigitsCountTheSameAsWords() throws {
        let a = try XCTUnwrap(proposal("3 coffees today", tag: .caffeine))
        let b = try XCTUnwrap(proposal("three coffees today", tag: .caffeine))
        XCTAssertEqual(a.quantity, 3)
        XCTAssertEqual(b.quantity, 3)
    }

    func testMinutesSurviveRatherThanRoundingToTheHour() throws {
        let caffeine = try XCTUnwrap(proposal("coffee at 4:30 pm", tag: .caffeineLate))
        XCTAssertEqual(caffeine.eventClockMinutes, 16 * 60 + 30)
    }

    func testAHardWorkoutCarriesItsIntensity() throws {
        let workout = try XCTUnwrap(proposal("hard workout at 8 pm", tag: .hardTraining))
        XCTAssertEqual(try XCTUnwrap(workout.intensity), 0.85, accuracy: 0.001)
        XCTAssertEqual(workout.eventClockMinutes, 20 * 60)
    }

    // MARK: - What is deliberately not read

    /// "A coffee" is grammar, not a count. Reading it as one would put every
    /// unquantified night in the one-cup band.
    func testAnArticleIsNotACount() throws {
        let caffeine = try XCTUnwrap(proposal("had a coffee", tag: .caffeine))
        XCTAssertNil(caffeine.quantity)
    }

    func testAPlainMentionCarriesNoQuantity() throws {
        let caffeine = try XCTUnwrap(proposal("coffee today", tag: .caffeine))
        XCTAssertNil(caffeine.quantity)
        XCTAssertNil(caffeine.eventClockMinutes)
    }

    /// A number in another clause is not this behaviour's count.
    func testANumberElsewhereInTheSentenceIsNotACount() throws {
        let caffeine = try XCTUnwrap(proposal("slept 6 hours, then coffee", tag: .caffeine))
        XCTAssertNil(caffeine.quantity)
    }

    /// A behaviour that did not happen has no quantity, no time and no
    /// intensity -- detail about an event nobody had.
    func testANegativeAnswerCarriesNoDetail() throws {
        let caffeine = try XCTUnwrap(proposal("no coffee after 2", tag: .caffeine))
        XCTAssertEqual(caffeine.state, .no)
        XCTAssertNil(caffeine.quantity)
        XCTAssertNil(caffeine.eventClockMinutes)
        XCTAssertNil(caffeine.intensity)
    }

    /// A hard cup of coffee is not a thing. Intensity is stored only where
    /// the word means something about the behaviour.
    func testIntensityIsOnlyReadForBehavioursItMeansSomethingFor() throws {
        let caffeine = try XCTUnwrap(proposal("hard day, lots of coffee", tag: .caffeine))
        XCTAssertNil(caffeine.intensity)
        XCTAssertFalse(BehaviorTag.caffeine.takesIntensity)
        XCTAssertTrue(BehaviorTag.hardTraining.takesIntensity)
    }

    // MARK: - Anchoring to the night

    /// An evening time belongs to the evening before the morning the night is
    /// filed under: "coffee at 5" on the night ending Tuesday was Monday 17:00.
    func testAnEveningTimeLandsOnTheEveningBeforeTheMorning() throws {
        let caffeine = try XCTUnwrap(proposal("coffee at 5 pm", tag: .caffeineLate))
        let detail = try XCTUnwrap(caffeine.detail(onNightDay: nightDay, calendar: calendar))
        let event = try XCTUnwrap(detail.eventTime)
        XCTAssertEqual(calendar.component(.day, from: event), 14)
        XCTAssertEqual(calendar.component(.hour, from: event), 17)
    }

    func testAMorningTimeLandsOnTheMorningItself() throws {
        let light = try XCTUnwrap(proposal("morning walk at 7 am", tag: .morningDaylight))
        let detail = try XCTUnwrap(light.detail(onNightDay: nightDay, calendar: calendar))
        let event = try XCTUnwrap(detail.eventTime)
        XCTAssertEqual(calendar.component(.day, from: event), 15)
        XCTAssertEqual(calendar.component(.hour, from: event), 7)
    }

    /// The clock time is anchored once, in the night's own zone, and read back
    /// in that zone. Re-deriving an hour later, wherever the phone happens to
    /// be, is the bug `timeZoneIdentifier` exists to prevent.
    func testTheAnchoredTimeReadsBackAsTheHourThatWasSaid() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let caffeine = try XCTUnwrap(proposal("coffee at 5 pm", tag: .caffeineLate))
        let detail = try XCTUnwrap(caffeine.detail(onNightDay: nightDay, calendar: tokyo))
        XCTAssertEqual(detail.eventClockMinutes(calendar: tokyo), 17 * 60)
    }

    func testAProposalWithNothingStructuredHasNoDetailAtAll() throws {
        let caffeine = try XCTUnwrap(proposal("coffee today", tag: .caffeine))
        XCTAssertNil(caffeine.detail(onNightDay: nightDay, calendar: calendar))
    }

    // MARK: - The value type

    func testAZeroOrNegativeQuantityIsNotAQuantity() {
        XCTAssertNil(BehaviorDetail(quantity: 0).quantity)
        XCTAssertNil(BehaviorDetail(quantity: -2).quantity)
    }

    func testIntensityIsClampedToItsRange() {
        XCTAssertEqual(BehaviorDetail(intensity: 4).intensity, 1)
        XCTAssertEqual(BehaviorDetail(intensity: -1).intensity, 0)
    }

    func testAnEmptyDetailKnowsItIsEmpty() {
        XCTAssertTrue(BehaviorDetail().isEmpty)
        XCTAssertFalse(BehaviorDetail(quantity: 1).isEmpty)
    }

    func testABlankUnitIsNoUnit() {
        XCTAssertNil(BehaviorDetail(quantity: 2, unit: "   ").unit)
    }

    func testTheSummaryReadsAsSomethingSomebodyWouldSay() throws {
        let detail = BehaviorDetail(quantity: 2, unit: "coffees")
        XCTAssertEqual(detail.summary(calendar: calendar), "2 coffees")
        XCTAssertNil(BehaviorDetail().summary(calendar: calendar))
    }

    func testIntensityIsSummarisedInWordsRatherThanAsANumber() {
        XCTAssertEqual(BehaviorDetail.intensityLabel(0.85), "hard")
        XCTAssertEqual(BehaviorDetail.intensityLabel(0.2), "easy")
        XCTAssertEqual(BehaviorDetail.intensityLabel(0.5), "moderate")
        XCTAssertFalse(
            BehaviorDetail(intensity: 0.85).summary(calendar: calendar)?.contains("0.8") == true
        )
    }

    func testADetailSurvivesARoundTripThroughJSON() throws {
        let detail = BehaviorDetail(
            quantity: 2, unit: "coffees", eventTime: nightDay, intensity: 0.5
        )
        let data = try JSONEncoder().encode(detail)
        XCTAssertEqual(try JSONDecoder().decode(BehaviorDetail.self, from: data), detail)
    }
}

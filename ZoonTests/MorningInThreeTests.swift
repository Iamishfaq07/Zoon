import XCTest

/// The three sentences Today opens with.
///
/// They live in `Shared` rather than in the view because each makes a claim
/// with a threshold behind it, and a threshold written into a `Text(...)` is
/// a threshold nobody tests.
final class MorningInThreeTests: XCTestCase {

    private func summary(
        asleep: Double = 452,
        score: Int = 81,
        band: String = "Good",
        bodySignals: String? = nil,
        debt: Double = 0,
        needIsLearned: Bool = true
    ) -> MorningInThree {
        MorningInThree.build(
            timeAsleepMinutes: asleep,
            flagshipScore: score,
            flagshipBand: band,
            bodySignalsHeadline: bodySignals,
            debtMinutes: debt,
            hasEnoughHistoryForNeed: needIsLearned
        )
    }

    func testThereAreExactlyThreeLinesAndTheyAreLabelled() {
        let result = summary()
        XCTAssertEqual(result.lines.map(\.label), ["SLEEP", "BODY", "TODAY"])
        for line in result.lines {
            XCTAssertFalse(line.headline.isEmpty, "\(line.label) has no answer")
        }
    }

    // MARK: - SLEEP

    func testSleepLeadsWithDurationAndCarriesTheScoreSecondarily() {
        let result = summary(asleep: 452, score: 81, band: "Good")
        XCTAssertEqual(result.sleep.headline, SleepNightFeatures.formatMinutes(452))
        XCTAssertEqual(result.sleep.detail, "Good · 81")
    }

    /// A snapshot too old to carry a band must not render "· 81" with nothing
    /// in front of it.
    func testAnEmptyBandLeavesNoStrandedSeparator() {
        XCTAssertNil(summary(band: "").sleep.detail)
    }

    // MARK: - BODY

    /// The common case, and it gets said rather than left blank. "Nothing is
    /// wrong" is information; an empty line is not.
    func testNothingUnusualIsStatedPlainly() {
        let result = summary(bodySignals: nil)
        XCTAssertEqual(result.body.headline, "Signals look typical")
        XCTAssertNil(result.body.detail)
    }

    func testAnActiveSignalCarriesHealthRadarsOwnSentence() {
        let headline = "Resting heart rate has been higher than usual for three nights."
        let result = summary(bodySignals: headline)
        XCTAssertEqual(result.body.headline, "Worth a look")
        XCTAssertEqual(result.body.detail, headline)
    }

    // MARK: - TODAY

    /// The line that makes the strongest claim, and the one most able to be
    /// wrong: it is a statement about a shortfall against a number Zoon
    /// estimated.
    func testARealShortfallIsNamedWithItsSize() throws {
        let result = summary(debt: 95)
        XCTAssertTrue(result.today.headline.contains(SleepNightFeatures.formatMinutes(95)), result.today.headline)
        XCTAssertTrue(try XCTUnwrap(result.today.detail).contains("your own estimated sleep need"))
    }

    func testASmallShortfallIsNotWorthOpeningTheDayWith() {
        let result = summary(debt: MorningInThree.debtWorthMentioningMinutes - 1)
        XCTAssertEqual(result.today.headline, "You're on top of your sleep need")
    }

    func testTheThresholdIsInclusive() {
        let result = summary(debt: MorningInThree.debtWorthMentioningMinutes)
        XCTAssertTrue(result.today.headline.contains("behind"), result.today.headline)
    }

    /// The refusal that matters. Before the need is learned it is the
    /// Settings default, and "you're 2h behind" against a number nobody
    /// measured is the sort of confident-sounding nonsense the rest of this
    /// app declines to print.
    func testNoShortfallIsClaimedBeforeTheNeedIsLearned() throws {
        // The property, rather than a word. With the need unlearned the line
        // cannot vary with the debt -- if it did, it would be making a claim
        // about a number nobody has measured.
        //
        // An earlier version of this test asserted the copy never contains
        // "behind", which the copy fails and should: "how far ahead or behind
        // you are" is a statement that Zoon *cannot* say yet, not a shortfall.
        // Substring matching could not tell those apart. This can.
        let none = summary(debt: 0, needIsLearned: false)
        let large = summary(debt: 600, needIsLearned: false)
        XCTAssertEqual(none.today, large.today)

        XCTAssertEqual(large.today.headline, "Still learning your sleep need")
        // No quantity is stated, which is what claiming a shortfall requires.
        let detail = try XCTUnwrap(large.today.detail)
        XCTAssertFalse(
            detail.contains(where: \.isNumber),
            "a shortfall was quantified against an unlearned need: \(detail)"
        )
    }

    /// Whatever the state, TODAY always says something actionable or
    /// explicitly says it cannot yet. It is never blank.
    func testTodayAlwaysCarriesAnExplanation() {
        for needIsLearned in [true, false] {
            for debt in [Double(0), 39, 40, 200] {
                let result = summary(debt: debt, needIsLearned: needIsLearned)
                XCTAssertNotNil(
                    result.today.detail,
                    "debt \(debt), learned \(needIsLearned) produced no detail"
                )
            }
        }
    }

    // MARK: - What it must not prescribe (V10 item 12)

    /// "An earlier night beats a lie-in" is true of an office worker with a
    /// fixed alarm and false of a night-shift nurse, someone mid-timezone
    /// shift, a parent whose evening is not theirs, or anyone on a recovery
    /// day. Zoon knows the shortfall; it does not know which end of the night
    /// is available.
    func testAShortfallNamesTheGoalRatherThanPrescribingAnEarlierBedtime() throws {
        let behind = summary(debt: 95)
        let raw = try XCTUnwrap(behind.today.detail)
        let detail = raw.lowercased()

        XCTAssertTrue(detail.contains("sleep opportunity"),
                      "the shortfall line stopped naming what to protect: \(raw)")
        for prescription in ["earlier night", "lie-in", "lie in", "go to bed earlier"] {
            XCTAssertFalse(
                detail.contains(prescription),
                "prescribed a method the context may not allow: \(raw)"
            )
        }
    }

    /// The shortfall itself is still stated plainly -- this is about *how* to
    /// close it, not about softening the fact that there is a gap.
    func testTheShortfallIsStillStatedPlainly() {
        let behind = summary(debt: 95)
        XCTAssertTrue(behind.today.headline.lowercased().contains("behind"))
    }

    /// Every line, in every state, must leave the method to context.
    func testNoLineEverPrescribesAnEarlierBedtime() {
        let states = [
            summary(debt: 0),
            summary(debt: 95),
            summary(debt: 260),
            summary(needIsLearned: false),
            summary(bodySignals: "Resting heart rate has been higher than usual.")
        ]
        for state in states {
            for line in state.lines {
                let text = (line.headline + " " + (line.detail ?? "")).lowercased()
                XCTAssertFalse(text.contains("earlier night"), "prescribed in \(line.label)")
                XCTAssertFalse(text.contains("lie-in"), "prescribed in \(line.label)")
            }
        }
    }
}

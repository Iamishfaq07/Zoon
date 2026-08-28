import XCTest

final class JournalCorrelatorTests: XCTestCase {

    private func observation(
        daysAgo: Int,
        tags: Set<BehaviorTag> = [],
        // Replaced an `isJournaled` flag that meant only "a JournalEntry
        // row exists" -- which the old model read as a confident no for
        // every untagged behaviour, though a row is created merely by
        // opening the journal screen. `true` now states what these fixtures
        // actually mean: the whole list was worked through, so tagged
        // behaviours are yes and every other one is an explicit no. `false`
        // means nothing was answered, so every behaviour is unknown.
        fullyAnswered: Bool = true,
        sleepPerformance: Double? = 80,
        isWeekend: Bool = false
    ) -> JournalCorrelator.Observation {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return JournalCorrelator.Observation(
            date: date,
            tags: tags,
            answers: fullyAnswered ? .fullyAnswered(tags: tags) : .none,
            recoveryPercent: 70,
            sleepPerformance: sleepPerformance,
            deepMinutes: 80,
            remMinutes: 90,
            efficiency: 90,
            wakeCount: 2,
            isWeekend: isWeekend,
            sleepDebtMinutes: 30,
            bedtimeHour: -1,
            alcoholicBeverages: nil,
            lateCaffeineMg: nil,
            measuredTimeZoneShift: false
        )
    }

    // MARK: - ExposureState

    func testTaggedNightIsYes() {
        let obs = observation(daysAgo: 0, tags: [.alcohol])
        XCTAssertEqual(obs.exposureState(for: .alcohol), .yes)
    }

    /// Inverted deliberately. This used to assert that tagging alcohol made
    /// caffeine a confident "no", on the reasoning that the night had been
    /// "reviewed". But a `JournalEntry` row is created by rendering the
    /// screen, so that inference turned a screen visit into twenty-two
    /// fabricated negatives. See `BehaviorEvidenceTests`.
    func testTaggingOneBehaviourLeavesAnotherUnknown() {
        let obs = observation(daysAgo: 0, tags: [.alcohol], fullyAnswered: false)
        XCTAssertEqual(obs.exposureState(for: .alcohol), .yes)
        XCTAssertEqual(obs.exposureState(for: .caffeineLate), .unknown)
    }

    /// The core fix: a night the user never opened the Journal on must
    /// never resolve to a confident "no" for a tag it doesn't carry --
    /// only "unknown."
    func testUnjournaledNightWithoutTagIsUnknown() {
        let obs = observation(daysAgo: 0, tags: [], fullyAnswered: false)
        XCTAssertEqual(obs.exposureState(for: .alcohol), .unknown)
    }

    /// A night the user genuinely worked through is a real "no" across the
    /// board. What changed is that this now has to be *stated* -- the
    /// `fullyAnswered` fixture below records an explicit no for every
    /// untagged behaviour, where the old `isJournaled` flag merely asserted
    /// a row existed.
    func testAFullyAnsweredNightIsNoForUntaggedBehaviours() {
        let obs = observation(daysAgo: 0, tags: [], fullyAnswered: true)
        XCTAssertEqual(obs.exposureState(for: .alcohol), .no)
    }

    /// And the same night with nothing answered is unknown, not no.
    func testAnUnansweredNightIsUnknown() {
        let obs = observation(daysAgo: 0, tags: [], fullyAnswered: false)
        XCTAssertEqual(obs.exposureState(for: .alcohol), .unknown)
    }

    func testMeasuredAlcoholUpgradesUnjournaledNightToYes() {
        let date = Date.now
        let obs = JournalCorrelator.Observation(
            date: date, tags: [], answers: .none, recoveryPercent: 70,
            sleepPerformance: 80, deepMinutes: 80, remMinutes: 90, efficiency: 90,
            wakeCount: 2, isWeekend: false, sleepDebtMinutes: 30, bedtimeHour: -1,
            alcoholicBeverages: 2, lateCaffeineMg: nil, measuredTimeZoneShift: false
        )
        XCTAssertEqual(obs.exposureState(for: .alcohol), .yes)
    }

    // MARK: - Matched-pair exclusion of unknown nights

    /// The regression this whole rewrite exists to prevent: an unjournaled
    /// night must never be usable as a "no" comparison night, even when
    /// there are plenty of them and very few genuine journaled "no" nights.
    func testUnknownNightsAreNeverUsedAsComparisons() {
        var observations: [JournalCorrelator.Observation] = []
        // 8 tagged (exposed) nights, alternating weekday assignment so the
        // hard weekend/weekday match constraint doesn't exhaust the pool
        // for either side.
        for i in 0..<8 {
            observations.append(observation(
                daysAgo: i, tags: [.alcohol], sleepPerformance: 60, isWeekend: i % 2 == 0
            ))
        }
        // Plenty of *unjournaled* nights with high performance -- if these
        // ever get treated as "no" comparisons, they'd pull the matched
        // delta toward zero (or reverse it) because they're not actually
        // known non-alcohol nights, just unreviewed ones.
        for i in 8..<40 {
            observations.append(observation(
                daysAgo: i, tags: [], fullyAnswered: false, sleepPerformance: 95, isWeekend: i % 2 == 0
            ))
        }
        // A handful of genuinely journaled "no" nights with performance
        // close to the exposed nights, so a real finding shouldn't clear
        // the effect-size bar either way -- the point of this test is
        // exclusion, not a specific direction of effect.
        for i in 40..<48 {
            observations.append(observation(
                daysAgo: i, tags: [], fullyAnswered: true, sleepPerformance: 62, isWeekend: i % 2 == 0
            ))
        }

        let findings = JournalCorrelator().findings(from: observations)
        // With too few genuine "no" nights per weekend/weekday bucket to
        // reach the matched-pair minimum, alcohol shouldn't produce a
        // finding at all -- it should fall to "still learning," not
        // silently borrow the unjournaled nights to manufacture one.
        XCTAssertFalse(findings.contains { $0.tag == .alcohol })
    }
}

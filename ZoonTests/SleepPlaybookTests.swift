import XCTest

final class SleepPlaybookTests: XCTestCase {

    func testTooFewNightsReturnsNil() {
        let outcomes = Array(repeating: 80.0, count: 10)
        let playbook = SleepPlaybook.build(outcomePerNight: outcomes, factorInputs: [])
        XCTAssertNil(playbook)
    }

    func testFactorPresentOnEveryBestNightSurfaces() {
        // 30 nights. Top quarter (best outcome) all have the factor present;
        // the rest mostly don't.
        var outcomes: [Double] = []
        var presence: [Bool?] = []
        for i in 0..<30 {
            let isTopQuarter = i < 8
            outcomes.append(isTopQuarter ? 95 : Double(50 + i))
            presence.append(isTopQuarter ? true : (i % 3 == 0))
        }
        let input = SleepPlaybook.FactorInput(id: "test", label: "Test factor", presencePerNight: presence)
        guard let playbook = SleepPlaybook.build(outcomePerNight: outcomes, factorInputs: [input]) else {
            return XCTFail("expected a playbook")
        }
        XCTAssertTrue(playbook.factors.contains { $0.id == "test" })
        let factor = playbook.factors.first { $0.id == "test" }
        XCTAssertGreaterThan(factor?.bestNightsRate ?? 0, factor?.otherNightsRate ?? 1)
    }

    /// The actual bug: `typicalRate` used to be computed over *all* known
    /// nights, including the best-quarter nights themselves, so a factor
    /// present on every best night still dragged its own "typical" rate up
    /// -- comparing best-vs-all-including-best instead of best-vs-rest.
    func testOtherNightsRateExcludesBestNightsThemselves() {
        // 32 nights, so the top quarter is exactly 8 nights (32 / 4) with
        // no tie at the boundary -- distinct outcomes throughout so which
        // 8 land in "best" is unambiguous. Factor present on every best
        // night, and on none of the rest -- a perfectly clean signal that
        // a best-vs-all computation would still understate.
        var outcomes: [Double] = []
        var presence: [Bool?] = []
        for i in 0..<32 {
            let isTopQuarter = i < 8
            outcomes.append(isTopQuarter ? Double(90 + i) : Double(20 + i))
            presence.append(isTopQuarter)
        }
        let input = SleepPlaybook.FactorInput(id: "clean", label: "Clean factor", presencePerNight: presence)
        guard let playbook = SleepPlaybook.build(outcomePerNight: outcomes, factorInputs: [input]),
              let factor = playbook.factors.first(where: { $0.id == "clean" }) else {
            return XCTFail("expected the factor to clear the bar")
        }
        XCTAssertEqual(factor.bestNightsRate, 1.0, accuracy: 0.001)
        // If the old bug were present, typicalRate would be 8/32 = 0.25
        // (the best nights folded into the "typical" pool). Excluding them
        // correctly, the other-nights rate is 0/24 = 0.
        XCTAssertEqual(factor.otherNightsRate, 0.0, accuracy: 0.001)
    }

    func testFactorWithNoRealDifferenceIsExcluded() {
        // Present roughly equally regardless of outcome -- no real signal.
        let outcomes = (0..<30).map { Double(50 + $0) }
        let presence: [Bool?] = (0..<30).map { $0 % 2 == 0 }
        let input = SleepPlaybook.FactorInput(id: "flat", label: "Flat factor", presencePerNight: presence)
        let playbook = SleepPlaybook.build(outcomePerNight: outcomes, factorInputs: [input])
        XCTAssertFalse(playbook?.factors.contains { $0.id == "flat" } ?? false)
    }

    func testUnknownPresenceIsExcludedFromRates() {
        var outcomes: [Double] = []
        var presence: [Bool?] = []
        for i in 0..<30 {
            let isTopQuarter = i < 8
            outcomes.append(isTopQuarter ? 95 : Double(50 + i))
            // Half of everything is "unknown" -- should still work off the
            // known half alone, not treat unknowns as absent.
            presence.append(i % 2 == 0 ? nil : isTopQuarter)
        }
        let input = SleepPlaybook.FactorInput(id: "sparse", label: "Sparse factor", presencePerNight: presence)
        let playbook = SleepPlaybook.build(outcomePerNight: outcomes, factorInputs: [input])
        // Known nights: 15 total (odd indices), 4 of which are top-quarter
        // (indices 1, 3, 5, 7) -- enough to clear every floor.
        XCTAssertNotNil(playbook)
    }

    func testFactorsAreSortedByEffectSizeDescending() {
        var outcomes: [Double] = []
        var strongPresence: [Bool?] = []
        var weakPresence: [Bool?] = []
        for i in 0..<40 {
            let isTopQuarter = i < 10
            outcomes.append(isTopQuarter ? 95 : Double(40 + i))
            // Strong: present on all 10 best nights, only 2 of the other
            // 30 -- bestRate 1.0, typicalRate (10 + 2) / 40 = 0.3, a 0.7 gap.
            strongPresence.append(isTopQuarter ? true : (i < 12))
            // Weak: present on 7 of 10 best nights, only 3 of the other
            // 30 -- bestRate 0.7, typicalRate (7 + 3) / 40 = 0.25, a 0.45
            // gap. Clears the 0.2 floor but is clearly smaller than
            // "strong"'s.
            weakPresence.append(isTopQuarter ? (i < 7) : (i < 13))
        }
        let inputs = [
            SleepPlaybook.FactorInput(id: "weak", label: "Weak", presencePerNight: weakPresence),
            SleepPlaybook.FactorInput(id: "strong", label: "Strong", presencePerNight: strongPresence)
        ]
        guard let playbook = SleepPlaybook.build(outcomePerNight: outcomes, factorInputs: inputs),
              playbook.factors.count == 2 else {
            return XCTFail("expected both factors to clear the bar")
        }
        XCTAssertEqual(playbook.factors.first?.id, "strong")
    }

    func testConfidenceReflectsSampleSizeAndEffectGap() {
        var outcomes: [Double] = []
        var strongPresence: [Bool?] = []
        var weakPresence: [Bool?] = []
        for i in 0..<40 {
            let isTopQuarter = i < 10
            outcomes.append(isTopQuarter ? 95 : Double(40 + i))
            // Strong: bestRate 1.0, otherRate 2/30 -- wide gap, full sample.
            strongPresence.append(isTopQuarter ? true : (i < 12))
            // Weak: bestRate 0.4 (4 of 10), otherRate 0.1 (3 of 30) -- a
            // 0.3 gap, clears the 0.2 floor but far thinner than "strong".
            weakPresence.append(isTopQuarter ? (i < 4) : (i < 13))
        }
        let inputs = [
            SleepPlaybook.FactorInput(id: "weak", label: "Weak", presencePerNight: weakPresence),
            SleepPlaybook.FactorInput(id: "strong", label: "Strong", presencePerNight: strongPresence)
        ]
        guard let playbook = SleepPlaybook.build(outcomePerNight: outcomes, factorInputs: inputs) else {
            return XCTFail("expected both factors to clear the bar")
        }
        let strong = playbook.factors.first { $0.id == "strong" }
        let weak = playbook.factors.first { $0.id == "weak" }
        XCTAssertEqual(strong?.confidence, .high)
        XCTAssertNotEqual(weak?.confidence, .high)
    }
}

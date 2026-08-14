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
        XCTAssertGreaterThan(factor?.bestNightsRate ?? 0, factor?.typicalRate ?? 1)
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
            strongPresence.append(isTopQuarter ? true : false)
            weakPresence.append(isTopQuarter ? (i % 2 == 0) : (i % 3 == 0))
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
}

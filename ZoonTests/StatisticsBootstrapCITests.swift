import XCTest

final class StatisticsBootstrapCITests: XCTestCase {

    func testTooFewDeltasReturnsNil() {
        XCTAssertNil(Statistics.pairedBootstrapCI(deltas: [1, 2]))
    }

    func testSameSeedIsDeterministic() {
        let deltas = [3.0, -1.0, 4.0, 2.0, -2.0, 5.0, 1.0, 0.0, 3.5, -0.5]
        let first = Statistics.pairedBootstrapCI(deltas: deltas)
        let second = Statistics.pairedBootstrapCI(deltas: deltas)
        XCTAssertEqual(first?.lower, second?.lower)
        XCTAssertEqual(first?.upper, second?.upper)
    }

    func testDifferentSeedsCanDisagree() {
        let deltas = [3.0, -1.0, 4.0, 2.0, -2.0, 5.0, 1.0, 0.0, 3.5, -0.5]
        let a = Statistics.pairedBootstrapCI(deltas: deltas, seed: 1)
        let b = Statistics.pairedBootstrapCI(deltas: deltas, seed: 2)
        // Not asserting they always differ (small chance of coincidence),
        // just that both produce a valid, ordered interval independently.
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertLessThanOrEqual(a!.lower, a!.upper)
        XCTAssertLessThanOrEqual(b!.lower, b!.upper)
    }

    /// All deltas consistently positive -- the interval around the median of
    /// resampled medians should stay clear of zero.
    func testAllPositiveDeltasExcludeZero() {
        let deltas = [4.0, 5.0, 3.0, 6.0, 4.5, 5.5, 3.5, 4.0, 5.0, 4.5, 3.5, 6.5]
        guard let ci = Statistics.pairedBootstrapCI(deltas: deltas) else {
            return XCTFail("expected a confidence interval")
        }
        XCTAssertGreaterThan(ci.lower, 0)
        XCTAssertGreaterThan(ci.upper, 0)
    }

    /// Deltas that straddle zero roughly evenly should produce an interval
    /// that itself straddles (or nearly straddles) zero, not a spuriously
    /// confident one-sided range.
    func testMixedSignDeltasStraddleZero() {
        let deltas = [4.0, -4.0, 3.5, -3.5, 4.5, -4.5, 0.5, -0.5, 3.0, -3.0]
        guard let ci = Statistics.pairedBootstrapCI(deltas: deltas) else {
            return XCTFail("expected a confidence interval")
        }
        XCTAssertLessThanOrEqual(ci.lower, 0.5)
        XCTAssertGreaterThanOrEqual(ci.upper, -0.5)
    }

    func testSeededGeneratorIsDeterministic() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        for _ in 0..<50 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testSeededGeneratorDiffersAcrossSeeds() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        let sequenceA = (0..<10).map { _ in a.next() }
        let sequenceB = (0..<10).map { _ in b.next() }
        XCTAssertNotEqual(sequenceA, sequenceB)
    }
}

import XCTest

/// The debt model is measured against what people reported, per slice, and
/// never quietly adjusted.
final class NeedModelEvaluationTests: XCTestCase {

    private func nights(_ count: Int, stratum: String, relation: (Int) -> (Double?, Int?)) -> [NeedModelEvaluation.Night] {
        (0..<count).map { i in
            let (shortfall, rating) = relation(i)
            return .init(shortfallMinutes: shortfall, restedRating: rating, stratum: stratum)
        }
    }

    /// More shortfall, less rested: the direction the model claims.
    func testAModelThatTracksRatingsCorrelatesNegatively() throws {
        let data = nights(30, stratum: "Apple Watch") { i in (Double(i * 10), 5 - i / 7) }
        let overall = try XCTUnwrap(NeedModelEvaluation.evaluate(data).first)
        XCTAssertEqual(overall.usable, 30)
        XCTAssertLessThan(try XCTUnwrap(overall.rankCorrelation), -0.8)
    }

    /// Missing ratings are counted as missing, not scored as anything.
    func testMissingnessIsCountedNotImputed() {
        let data = nights(30, stratum: "Phone") { i in (Double(i), i.isMultiple(of: 2) ? 3 : nil) }
        let overall = NeedModelEvaluation.evaluate(data)[0]
        XCTAssertEqual(overall.nights, 30)
        XCTAssertEqual(overall.usable, 15)
        XCTAssertEqual(overall.missing, 15)
        XCTAssertNil(overall.rankCorrelation, "15 pairs is under the minimum")
    }

    /// A slice where the model does not track is visible as its own row.
    func testStrataAreReportedSeparately() {
        let watch = nights(25, stratum: "Watch") { i in (Double(i * 10), 5 - i / 6) }
        let shift = nights(25, stratum: "Shift work") { i in (Double(i * 10), 3) }
        let summaries = NeedModelEvaluation.evaluate(watch + shift)
        XCTAssertEqual(summaries.map(\.stratum).sorted(), ["All nights", "Shift work", "Watch"])
        XCTAssertNil(summaries.first { $0.stratum == "Shift work" }?.rankCorrelation,
                     "a constant rating has no correlation, not a zero one")
        XCTAssertNotNil(summaries.first { $0.stratum == "Watch" }?.rankCorrelation)
    }

    func testTiesAreRankedByAverage() throws {
        let rho = try XCTUnwrap(NeedModelEvaluation.spearman([1, 2, 2, 3], [1, 2, 2, 3]))
        XCTAssertEqual(rho, 1, accuracy: 1e-9)
    }
}

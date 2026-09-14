import XCTest

/// A user's own correlation must contain only their own observations.
final class CycleRecoveryProvenanceTests: XCTestCase {

    private func starts(_ daysAgo: [Int]) -> [Date] {
        let calendar = Calendar.current
        return daysAgo.map { calendar.date(byAdding: .day, value: -$0, to: .now)! }
    }

    private func day(_ daysAgo: Int) -> Date {
        Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        )
    }

    /// The call site used `recoveryHistory[date] ?? 50`. A phase whose nights
    /// have no stored Recovery would then report a confident-looking mean of
    /// 50 — a number no night in it ever had.
    func testMissingRecoveryIsNotScoredAsFifty() {
        let nights: [(date: Date, recoveryPercent: Int?, sleepPerformance: Double)] =
            (0..<28).map { (date: day($0), recoveryPercent: nil, sleepPerformance: 85) }

        let rows = CyclePhaseCorrelation.compute(
            nights: nights, periodStarts: starts([0, 28, 56])
        )

        XCTAssertFalse(rows.isEmpty, "Sleep performance is still reportable")
        for row in rows {
            XCTAssertNil(row.avgRecoveryPercent,
                         "\(row.phase.label) invented a recovery mean from no scores")
            XCTAssertEqual(row.recoveryNightCount, 0)
        }
    }

    /// Present scores are averaged over themselves, not diluted by the
    /// nights that have none.
    func testRecoveryMeanUsesOnlyNightsThatHaveOne() {
        var nights: [(date: Date, recoveryPercent: Int?, sleepPerformance: Double)] = []
        for index in 0..<28 {
            // Four real scores of 80, the rest absent.
            nights.append((date: day(index),
                           recoveryPercent: index < 4 ? 80 : nil,
                           sleepPerformance: 85))
        }

        let rows = CyclePhaseCorrelation.compute(
            nights: nights, periodStarts: starts([0, 28, 56])
        )
        let scored = rows.filter { $0.avgRecoveryPercent != nil }
        for row in scored {
            let mean = try? XCTUnwrap(row.avgRecoveryPercent)
            XCTAssertEqual(mean ?? 0, 80, accuracy: 0.001,
                           "Averaged with absent nights this would fall toward 50")
            XCTAssertLessThanOrEqual(row.recoveryNightCount, row.nightCount)
        }
    }

    /// Below the three-observation floor a phase reports no recovery mean at
    /// all rather than a mean of one or two nights.
    func testRecoveryWithheldBelowThreeObservations() {
        var nights: [(date: Date, recoveryPercent: Int?, sleepPerformance: Double)] = []
        for index in 0..<28 {
            nights.append((date: day(index),
                           recoveryPercent: index == 0 ? 90 : nil,
                           sleepPerformance: 85))
        }
        let rows = CyclePhaseCorrelation.compute(
            nights: nights, periodStarts: starts([0, 28, 56])
        )
        for row in rows {
            XCTAssertNil(row.avgRecoveryPercent)
        }
    }
}

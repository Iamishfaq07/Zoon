import XCTest

/// "Ask Zoon about this" on a chart point is answered from the point.
///
/// The seeded question went through the Coach's router like typed text.
/// "Why was my recovery signal lower on September 12?" contains "recovery",
/// so it was answered with this morning's Recovery score; a sleep-debt point
/// got today's shortfall, a duration point last night's duration.
final class ChartQuestionAnswerTests: XCTestCase {

    private let tapped = Date(timeIntervalSince1970: 1_757_600_000) // mid-September 2025
    private var day: String { tapped.formatted(.dateTime.month(.wide).day()) }

    private func question(_ subject: ChartQuestion.Subject, value: Double, baseline: Double?, tolerance: Double? = nil) -> ChartQuestion {
        var q = ChartQuestion(subject: subject, selected: .init(date: tapped, value: value))
        q.baseline = baseline
        q.baselineNightCount = baseline == nil ? 0 : 12
        q.tolerance = tolerance
        q.nearby = [
            .init(date: tapped.addingTimeInterval(-86_400), value: baseline ?? value),
            .init(date: tapped.addingTimeInterval(86_400), value: baseline ?? value)
        ]
        q.sleep = "6h 40m asleep"
        return q
    }

    /// Every subject either chart can ask about: the answer names the value
    /// and the date, is never about "this morning" or "last night", and
    /// makes no causal or diagnostic claim.
    func testEverySubjectIsAnsweredAboutTheTappedPoint() {
        var subjects: [(ChartQuestion.Subject, Double, Double, Double?)] = TrendEngine.Metric.allCases.map {
            switch $0 {
            case .bedtime: (.trend($0), -30, -75, nil)
            case .duration: (.trend($0), 400, 460, nil)
            case .hrv: (.trend($0), 38, 55, nil)
            case .restingHeartRate: (.trend($0), 61, 54, nil)
            case .efficiency: (.trend($0), 78, 90, nil)
            case .sleepDebt: (.trend($0), 180, 60, nil)
            }
        }
        subjects += VitalsStatus.Kind.allCases.map { (.vital($0), 20, 10, 2) }

        for (subject, value, baseline, tolerance) in subjects {
            let q = question(subject, value: value, baseline: baseline, tolerance: tolerance)
            let answer = q.localAnswer
            XCTAssertTrue(answer.text.contains(day), "\(subject.rawValue): \(answer.text)")
            XCTAssertTrue(answer.text.contains(q.formatted(value)), "\(subject.rawValue): \(answer.text)")
            XCTAssertTrue(answer.text.contains(q.formatted(baseline)), "\(subject.rawValue): \(answer.text)")
            XCTAssertFalse(answer.text.contains("This morning"), answer.text)
            XCTAssertFalse(answer.text.lowercased().contains("last night"), answer.text)
            XCTAssertFalse(DiagnosticLanguageGuard.rejects(answer.text), "\(subject.rawValue): \(answer.text)")
            XCTAssertTrue(answer.timeframe.hasPrefix("Night of"), answer.timeframe)
        }
    }

    func testAClearDropSaysHowFarAndOutsideTheRange() {
        let answer = question(.trend(.hrv), value: 38, baseline: 55).localAnswer
        XCTAssertTrue(answer.text.contains("lower than your usual"), answer.text)
        XCTAssertTrue(answer.text.contains("outside your typical range"), answer.text)
        XCTAssertTrue(answer.text.contains("12 nights"), answer.text)
        XCTAssertTrue(answer.text.contains("6h 40m asleep"), answer.text)
    }

    func testATypicalPointSaysSo() {
        let answer = question(.trend(.hrv), value: 54, baseline: 55).localAnswer
        XCTAssertTrue(answer.text.contains("within your typical range"), answer.text)
        XCTAssertFalse(answer.text.contains("outside"), answer.text)
    }

    func testNoBaselineIsStatedNotImplied() {
        let answer = question(.trend(.hrv), value: 38, baseline: nil).localAnswer
        XCTAssertTrue(answer.text.contains("no established baseline"), answer.text)
    }

    /// A bedtime is later or earlier, not higher or lower.
    func testBedtimeIsLaterOrEarlier() {
        let later = question(.trend(.bedtime), value: -10, baseline: -70).localAnswer
        XCTAssertTrue(later.text.contains("later than your usual"), later.text)
        XCTAssertFalse(later.text.contains("higher"), later.text)
    }

    /// The seeded question itself must not reach Recovery through the
    /// router either, for the paths that still classify it.
    func testTheHRVChartQuestionRoutesToHRVNotRecovery() {
        let q = question(.trend(.hrv), value: 38, baseline: 55)
        XCTAssertEqual(CoachToolCatalog.interpret(q.question)?.kind, .getHRV, q.question)
    }
}

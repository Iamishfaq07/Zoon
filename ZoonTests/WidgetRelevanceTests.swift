import XCTest

/// What the iOS Smart Stack is told about each widget.
///
/// The defect these were written for: all four widgets in the extension
/// shared one provider and therefore one score, computed purely from how
/// recently the phone had written a snapshot. Freshness is not relevance --
/// it says the data is current, not that *this* number is the one someone
/// wants now -- and four surfaces returning the same number at the same time
/// give the system nothing to rank.
///
/// That is word for word the defect `SurfaceRelevance` was written to fix on
/// the watch. It survived on iOS through a release because the type that
/// fixed it was called `WatchRelevance`, so this suite also pins the two
/// platforms to one table of day-parts.
final class WidgetRelevanceTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 12
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func score(
        _ kind: SurfaceRelevance.Kind,
        hour: Int,
        staleHours: Double = 0,
        isPlaceholder: Bool = false,
        nap: Bool = false,
        shiftWork: Bool = false
    ) -> Int {
        let now = date(hour: hour)
        return WidgetRelevance.score(
            for: kind,
            isPlaceholder: isPlaceholder,
            now: now,
            generatedAt: now.addingTimeInterval(-staleHours * 3600),
            isNapRunning: nap,
            isShiftWorkModeEnabled: shiftWork,
            calendar: calendar
        )
    }

    // MARK: - Four widgets, four answers

    /// The whole point. At any given hour the four surfaces must not all
    /// return the same number, or the Smart Stack is choosing at random.
    func testTheFourWidgetsDoNotAllScoreTheSame() {
        let surfaces: [SurfaceRelevance.Kind] = [.lastNight, .sleepDebt, .tonight, .bodySignals]
        for hour in [8, 14, 20] {
            let scores = Set(surfaces.map { score($0, hour: hour) })
            XCTAssertGreaterThan(
                scores.count, 1,
                "every widget returned the same score at \(hour):00 -- nothing to rank"
            )
        }
    }

    func testLastNightLeadsInTheMorning() {
        XCTAssertGreaterThan(score(.lastNight, hour: 8), score(.tonight, hour: 8))
        XCTAssertGreaterThan(score(.lastNight, hour: 8), score(.sleepDebt, hour: 8))
    }

    /// Debt shares the evening with Tonight on purpose: it is the number that
    /// decides what time to go to bed, a question about the night ahead.
    func testDebtAndTonightLeadInTheEvening() {
        XCTAssertGreaterThan(score(.sleepDebt, hour: 21), score(.lastNight, hour: 21))
        XCTAssertGreaterThan(score(.tonight, hour: 21), score(.lastNight, hour: 21))
    }

    // MARK: - Freshness still gates, rather than deciding

    /// The judgment worth keeping from the old version: when a surface
    /// matters and whether its data is current are different questions, and a
    /// stale number is not worth raising however well its hour matches.
    func testAStaleSnapshotCannotBePromotedByItsWindow() {
        let fresh = score(.lastNight, hour: 8, staleHours: 1)
        let stale = score(.lastNight, hour: 8, staleHours: WidgetRelevance.staleAfterHours + 1)
        XCTAssertGreaterThan(fresh, stale)
        XCTAssertLessThanOrEqual(Float(stale), SurfaceRelevance.outOfWindowScore)
    }

    /// A snapshot dated in the future is not fresh, it is wrong -- a clock
    /// change or a corrupt read. It must not score as the freshest possible.
    func testASnapshotFromTheFutureIsTreatedAsStale() {
        XCTAssertLessThanOrEqual(
            Float(score(.lastNight, hour: 8, staleHours: -5)),
            SurfaceRelevance.outOfWindowScore
        )
    }

    func testSampleDataNeverCompetes() {
        for hour in [8, 14, 21] {
            XCTAssertEqual(score(.lastNight, hour: hour, isPlaceholder: true), WidgetRelevance.placeholderScore)
        }
        XCTAssertLessThan(
            WidgetRelevance.placeholderScore, Int(SurfaceRelevance.outOfWindowScore),
            "sample data must rank below even an out-of-window real reading"
        )
    }

    // MARK: - Naps

    /// A nap suppresses the home-screen widgets the same way it suppresses the
    /// watch bundle: the stack has one slot, and during a nap it belongs to
    /// the Live Activity.
    func testARunningNapSuppressesTheWidgets() {
        XCTAssertLessThan(
            score(.lastNight, hour: 8, nap: true),
            score(.lastNight, hour: 8, nap: false)
        )
    }

    // MARK: - When the morning is not the morning

    /// The regression day-part windows would have caused, and the signal that
    /// prevents it.
    ///
    /// A shift worker waking at three in the afternoon would find *last
    /// night* out of window at the one moment it is most wanted. The obvious
    /// repair -- promote whatever synced recently -- is wrong: `generatedAt`
    /// is when the app last refreshed, not when a night was processed, so it
    /// would go high every time someone opened the app. `isShiftWorkModeEnabled`
    /// is the person having said so themselves, which is better evidence than
    /// any proxy derived from a refresh timestamp.
    func testShiftWorkKeepsLastNightAvailableOutsideTheMorning() {
        let clockMorning = score(.lastNight, hour: 15, shiftWork: false)
        let shiftWorker = score(.lastNight, hour: 15, shiftWork: true)
        XCTAssertLessThan(clockMorning, shiftWorker)
        XCTAssertEqual(Float(shiftWorker), SurfaceRelevance.inWindowScore)
    }

    /// It lifts one surface, not the whole extension. Promoting all four
    /// would put back the defect this replaced, for the people most likely to
    /// have irregular nights.
    func testShiftWorkDoesNotLiftEveryWidget() {
        for kind in [SurfaceRelevance.Kind.tonight, .sleepDebt, .bodySignals] {
            XCTAssertEqual(
                score(kind, hour: 15, shiftWork: true),
                score(kind, hour: 15, shiftWork: false),
                "\(kind.rawValue) was lifted by a mode it has nothing to do with"
            )
        }
    }

    /// Shift work changes which hours count as this person's morning. It does
    /// not change whether a running nap or a stale reading outrank it.
    func testShiftWorkDoesNotOverrideANapOrStaleness() {
        XCTAssertLessThan(
            score(.lastNight, hour: 15, nap: true, shiftWork: true),
            score(.lastNight, hour: 15, nap: false, shiftWork: true)
        )
        XCTAssertLessThanOrEqual(
            Float(score(.lastNight, hour: 15, staleHours: WidgetRelevance.staleAfterHours + 1, shiftWork: true)),
            SurfaceRelevance.outOfWindowScore
        )
    }

    // MARK: - One table, two platforms

    /// The naming failure that let this bug live: a shared type called
    /// `WatchRelevance` reads as not applying to iOS. Both platforms now read
    /// the same windows, and this fails if one grows a private copy.
    func testBothPlatformsReadTheSameWindows() {
        for hour in 0..<24 {
            for kind in SurfaceRelevance.Kind.allCases where kind != .napTimer {
                let watch = SurfaceRelevance.score(
                    for: kind, at: date(hour: hour), calendar: calendar
                )
                let widget = score(kind, hour: hour)
                XCTAssertEqual(
                    Int(watch), widget,
                    "\(kind.rawValue) at \(hour):00 diverged between the platforms"
                )
            }
        }
    }
}

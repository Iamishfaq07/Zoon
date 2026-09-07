import XCTest

/// When each complication is worth the Smart Stack's attention.
///
/// The bug this replaces: every complication shared one score, computed from
/// how recently the phone had synced. That is a freshness signal, not a
/// relevance one -- and with all four scoring identically, the Smart Stack
/// had nothing to order them by, which is the same as not implementing
/// relevance at all.
final class SurfaceRelevanceTests: XCTestCase {

    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 14
        components.hour = hour
        components.minute = 30
        return Calendar.current.date(from: components)!
    }

    private func score(_ kind: SurfaceRelevance.Kind, hour: Int, nap: Bool = false) -> Float {
        SurfaceRelevance.score(for: kind, at: date(hour: hour), isNapRunning: nap)
    }

    // MARK: - The day's shape

    func testLastNightAndRecoveryLeadInTheMorning() {
        XCTAssertEqual(score(.lastNight, hour: 7), SurfaceRelevance.inWindowScore)
        XCTAssertEqual(score(.recovery, hour: 7), SurfaceRelevance.inWindowScore)
        XCTAssertEqual(score(.tonight, hour: 7), SurfaceRelevance.outOfWindowScore)
    }

    func testBodySignalsLeadsInTheAfternoon() {
        XCTAssertEqual(score(.bodySignals, hour: 15), SurfaceRelevance.inWindowScore)
        XCTAssertEqual(score(.lastNight, hour: 15), SurfaceRelevance.outOfWindowScore)
    }

    func testTonightLeadsInTheEvening() {
        XCTAssertEqual(score(.tonight, hour: 21), SurfaceRelevance.inWindowScore)
        XCTAssertEqual(score(.recovery, hour: 21), SurfaceRelevance.outOfWindowScore)
    }

    /// Every hour of the day belongs to exactly one window, so no hour
    /// leaves the stack with nothing raised.
    func testEveryHourRaisesSomething() {
        for hour in 0..<24 {
            let raised = SurfaceRelevance.Kind.allCases.filter {
                score($0, hour: hour) == SurfaceRelevance.inWindowScore
            }
            if (5..<24).contains(hour) {
                XCTAssertFalse(raised.isEmpty, "nothing is relevant at \(hour):00")
            }
        }
    }

    /// The small hours belong to no window on purpose. Someone looking at
    /// their watch at 3am is not being served by a cheerful recovery score,
    /// and last night's is not finished being slept yet.
    func testTheSmallHoursRaiseNothing() {
        for hour in 0..<5 {
            for kind in SurfaceRelevance.Kind.allCases {
                XCTAssertNotEqual(
                    score(kind, hour: hour), SurfaceRelevance.inWindowScore,
                    "\(kind.rawValue) claims 0\(hour):00"
                )
            }
        }
    }

    // MARK: - Never absent

    /// A complication scoring zero can be dropped entirely. Someone checking
    /// their recovery at 9pm should find it lower down, not missing.
    func testAnOutOfWindowComplicationIsStillReachable() {
        XCTAssertGreaterThan(score(.recovery, hour: 21), 0)
        XCTAssertGreaterThan(score(.tonight, hour: 7), 0)
        XCTAssertGreaterThan(score(.bodySignals, hour: 7), 0)
    }

    // MARK: - Naps

    /// The one surface here about something happening *now* rather than
    /// something already measured. A timer someone has to hunt for while it
    /// runs has failed at the one job a timer has.
    func testARunningNapOutranksEverything() {
        let nap = score(.napTimer, hour: 14, nap: true)
        XCTAssertEqual(nap, SurfaceRelevance.activeNapScore)
        for kind in SurfaceRelevance.Kind.allCases where kind != .napTimer {
            XCTAssertLessThan(score(kind, hour: 14, nap: true), nap)
        }
    }

    /// Suppressed rather than merely outranked: the stack shows one slot,
    /// and during a nap that slot belongs to the timer.
    func testARunningNapSuppressesItsOwnWindowsWinner() {
        XCTAssertEqual(score(.bodySignals, hour: 15, nap: true), SurfaceRelevance.outOfWindowScore)
        XCTAssertEqual(score(.bodySignals, hour: 15), SurfaceRelevance.inWindowScore)
    }

    /// A nap timer with no nap running is not "quiet", it is nothing. This
    /// is the one kind allowed to score zero, because a stopped timer is not
    /// information someone might still want further down the stack.
    func testANapTimerWithNoNapScoresNothing() {
        XCTAssertEqual(score(.napTimer, hour: 14), 0)
        XCTAssertEqual(score(.napTimer, hour: 7), 0)
    }
}

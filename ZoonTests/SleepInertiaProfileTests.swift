import XCTest

final class SleepInertiaProfileTests: XCTestCase {

    private func session(
        daysAgo: Int,
        minutesSinceWaking: Double,
        median: Double
    ) -> AlertnessCheck.Session {
        AlertnessCheck.Session(
            date: Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            medianMilliseconds: median,
            iqrMilliseconds: 40,
            lapses: 0,
            falseStarts: 0,
            trials: 6,
            minutesSinceWaking: minutesSinceWaking
        )
    }

    func testTooFewSessionsProducesNothing() {
        let sessions = (0..<5).map { session(daysAgo: $0, minutesSinceWaking: 20, median: 380) }
        XCTAssertNil(SleepInertiaProfile.learn(sessions: sessions))
    }

    func testPracticeSessionsAreNotEvidenceOfARamp() {
        // Three slow practice runs at 10 minutes, then later-morning checks
        // that would otherwise look like a dramatic improvement.
        var sessions: [AlertnessCheck.Session] = (0..<3).map {
            session(daysAgo: 20 - $0, minutesSinceWaking: 10, median: 520)
        }
        sessions += (0..<8).map {
            session(daysAgo: 8 - $0, minutesSinceWaking: 100, median: 310)
        }
        XCTAssertNil(SleepInertiaProfile.learn(sessions: sessions),
                     "without early post-practice checks there is no ramp to report")
    }

    func testARealMorningRampIsDescribedAsAnAssociation() throws {
        var sessions: [AlertnessCheck.Session] = (0..<AlertnessCheck.practiceSessions).map {
            session(daysAgo: 30 - $0, minutesSinceWaking: 15, median: 480)
        }
        // After practice: slow in the first 20 minutes, settled after 40.
        sessions += (0..<4).map { session(daysAgo: 16 - $0, minutesSinceWaking: 12, median: 430) }
        sessions += (0..<4).map { session(daysAgo: 12 - $0, minutesSinceWaking: 45, median: 320) }
        sessions += (0..<4).map { session(daysAgo: 8 - $0, minutesSinceWaking: 110, median: 310) }

        let result = try XCTUnwrap(SleepInertiaProfile.learn(sessions: sessions))
        XCTAssertGreaterThanOrEqual(result.sessionCount, SleepInertiaProfile.minimumSessions)
        XCTAssertFalse(result.sentence.lowercased().contains("neurolog"))
        XCTAssertTrue(result.caveat.lowercased().contains("association"))
        XCTAssertTrue(result.sentence.lowercased().contains("waking"))
        XCTAssertLessThan(result.settleLowMinutes, SleepInertiaProfile.laterMorningMinutes)
    }

    func testCopyRefusesMedicalClaims() throws {
        var sessions: [AlertnessCheck.Session] = (0..<3).map {
            session(daysAgo: 20 - $0, minutesSinceWaking: 15, median: 400)
        }
        sessions += (0..<5).map { session(daysAgo: 12 - $0, minutesSinceWaking: 25, median: 360) }
        sessions += (0..<5).map { session(daysAgo: 6 - $0, minutesSinceWaking: 100, median: 330) }
        let result = try XCTUnwrap(SleepInertiaProfile.learn(sessions: sessions))
        for banned in AlertnessCheck.bannedClaims {
            XCTAssertFalse(result.sentence.lowercased().contains(banned), result.sentence)
            XCTAssertFalse(result.caveat.lowercased().contains(banned), result.caveat)
        }
    }
}

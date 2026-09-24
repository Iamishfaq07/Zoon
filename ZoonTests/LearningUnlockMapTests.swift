import XCTest

/// Audit §17.5: the unlock map states the engines' real thresholds.
final class LearningUnlockMapTests: XCTestCase {

    private func threshold(_ id: String) -> Int? {
        LearningUnlockMap.milestones.first { $0.id == id }?.requiredNights
    }

    /// Read from the engines, so a change there changes the promise here.
    func testThresholdsAreTheEnginesOwn() {
        XCTAssertEqual(threshold("stagePattern"), SleepIntelligenceScore.minimumStageBaselineNights)
        XCTAssertEqual(threshold("regularity"), SleepRegularity.minimumNights)
        XCTAssertEqual(threshold("sleepHealth"), SleepHealth.minimumNights)
        XCTAssertEqual(threshold("personalWASO"), RecoveryDayPlan.minimumHistoryNights)
        XCTAssertEqual(threshold("bodyClock"), BodyClock.minimumNights)
        XCTAssertEqual(threshold("forecasts"), UncertaintyForecast.minimumNights)
        XCTAssertEqual(threshold("playbook"), SleepPlaybook.minimumNights)
    }

    func testMilestonesAreInUnlockOrder() {
        let nights = LearningUnlockMap.milestones.map(\.requiredNights)
        XCTAssertEqual(nights, nights.sorted())
        XCTAssertEqual(Set(LearningUnlockMap.milestones.map(\.id)).count, LearningUnlockMap.milestones.count)
    }

    func testNoHistoryUnlocksNothingAndPointsAtTheFirstStep() {
        let progress = LearningUnlockMap.progress(nightCount: 0)
        XCTAssertFalse(progress.contains { $0.state == .unlocked })
        let first = LearningUnlockMap.milestones[0]
        XCTAssertEqual(progress.first?.state, .next(remaining: first.requiredNights))
    }

    /// Two engines unlock at the same count; both are "next", neither "later".
    func testTiedThresholdsShareNext() {
        let progress = LearningUnlockMap.progress(nightCount: SleepIntelligenceScore.minimumStageBaselineNights)
        let week = progress.filter { $0.milestone.requiredNights == SleepRegularity.minimumNights }
        XCTAssertGreaterThanOrEqual(week.count, 2)
        for item in week {
            XCTAssertEqual(item.state, .next(remaining: SleepRegularity.minimumNights - SleepIntelligenceScore.minimumStageBaselineNights))
        }
        XCTAssertEqual(progress.filter { $0.state == .unlocked }.map(\.milestone.id), ["stagePattern"])
    }

    func testExactlyAtTheThresholdIsUnlocked() {
        let progress = LearningUnlockMap.progress(nightCount: BodyClock.minimumNights)
        let bodyClock = progress.first { $0.milestone.id == "bodyClock" }
        XCTAssertEqual(bodyClock?.state, .unlocked)
    }

    func testEverythingUnlocksEventually() {
        let most = LearningUnlockMap.milestones.map(\.requiredNights).max() ?? 0
        XCTAssertTrue(LearningUnlockMap.progress(nightCount: most).allSatisfy { $0.state == .unlocked })
    }

    /// Nights, never dates: nothing in the copy promises a day.
    func testCopyCountsNightsAndNamesNoDates() {
        XCTAssertEqual(LearningUnlockMap.remainingCopy(1), "1 more night")
        XCTAssertEqual(LearningUnlockMap.remainingCopy(3), "3 more nights")
        let months = Calendar(identifier: .gregorian).monthSymbols + Calendar(identifier: .gregorian).weekdaySymbols
        for milestone in LearningUnlockMap.milestones {
            for word in months {
                XCTAssertFalse(milestone.detail.contains(word), "\(milestone.id) mentions \(word)")
            }
            XCTAssertFalse(DiagnosticLanguageGuard.rejects(milestone.detail), milestone.detail)
        }
    }
}

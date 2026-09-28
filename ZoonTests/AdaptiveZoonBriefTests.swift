import XCTest

final class AdaptiveZoonBriefTests: XCTestCase {

    func testMorningUsesDurationAndDoesNotInventRecovery() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 360, sleepDebtMinutes: 80)
        let brief = AdaptiveZoonBrief.make(
            phase: .morning,
            night: night,
            recoveryPercent: nil,
            energy: nil,
            load: nil,
            tonightBedtime: nil
        )
        XCTAssertTrue(brief.headline.lowercased().contains("asleep") || brief.headline.lowercased().contains("6h"))
        XCTAssertTrue(brief.headline.lowercased().contains("not ready") || brief.confidence.lowercased().contains("duration"))
        XCTAssertFalse(brief.headline.contains("78"))
    }

    func testMorningWithRecoveryMentionsTheNightNotLiveCapacity() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 360)
        let brief = AdaptiveZoonBrief.make(
            phase: .morning,
            night: night,
            recoveryPercent: 74,
            energy: 60,
            load: 4,
            tonightBedtime: nil
        )
        XCTAssertTrue(brief.headline.lowercased().contains("short"))
        XCTAssertTrue(brief.why?.lowercased().contains("not how you feel this afternoon") == true)
    }

    func testDayDoesNotPretendMissingEnergyIsTypical() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450)
        let brief = AdaptiveZoonBrief.make(
            phase: .day,
            night: night,
            recoveryPercent: 80,
            energy: nil,
            load: nil,
            tonightBedtime: nil
        )
        XCTAssertTrue(brief.headline.lowercased().contains("not available"))
        XCTAssertFalse(brief.headline.lowercased().contains("typical"))
        XCTAssertTrue(brief.dataUsed.isEmpty)
    }

    func testEveningProtectsTheUpcomingWindow() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 400, sleepDebtMinutes: 60)
        let bed = Date().addingTimeInterval(90 * 60)
        let brief = AdaptiveZoonBrief.make(
            phase: .evening,
            night: night,
            recoveryPercent: 70,
            energy: 40,
            load: 6,
            tonightBedtime: bed,
            now: Date()
        )
        XCTAssertTrue(brief.headline.lowercased().contains("protect"))
        XCTAssertTrue(brief.dataUsed.contains("Tonight plan"))
        XCTAssertFalse(brief.why?.lowercased().contains("diagnos") == true)
    }

    func testLocallyCorrectedNightIsNamedInConfidence() {
        var night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 420)
        night.timingProvenance = .locallyCorrected
        let brief = AdaptiveZoonBrief.make(
            phase: .morning,
            night: night,
            recoveryPercent: 70,
            energy: nil,
            load: nil,
            tonightBedtime: nil
        )
        XCTAssertTrue(brief.confidence.lowercased().contains("locally corrected"))
    }

    /// The evening brief states the shortfall Today's ring shows, not the
    /// debt carried into last night: the two differ by last night itself.
    func testEveningShortfallIsTheOneTheRingShows() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 452, sleepDebtMinutes: 95)
        let brief = AdaptiveZoonBrief.make(
            phase: .evening,
            night: night,
            recoveryPercent: nil,
            energy: nil,
            load: nil,
            tonightBedtime: nil,
            shortfallMinutes: 117
        )
        XCTAssertTrue(brief.headline.contains("1h 57m"), brief.headline)
        XCTAssertFalse(brief.headline.contains("1h 35m"), brief.headline)
    }

    // MARK: - Recovery arrives gated

    /// First week: the engine still computes a number (sleep performance
    /// re-normalised), but there is no baseline to be "close to".
    func testBuildingBaselineMakesNoPhysiologyClaim() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 432)
        let brief = AdaptiveZoonBrief.make(
            phase: .night,
            night: night,
            recovery: .buildingBaseline(nights: 3, required: 7),
            energy: nil,
            load: nil,
            tonightBedtime: nil
        )
        XCTAssertTrue(brief.headline.contains("not ready"), brief.headline)
        XCTAssertFalse(brief.headline.contains("physiology stayed"), brief.headline)
        XCTAssertEqual(brief.dataUsed, ["sleep duration"])
    }

    /// No HRV or resting heart rate: say what is missing instead of "not
    /// ready yet", which would never become true for this person.
    func testLimitedRecoveryNamesTheMissingHeartData() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 432)
        let brief = AdaptiveZoonBrief.make(
            phase: .morning,
            night: night,
            recovery: .limited(reason: "No HRV last night."),
            energy: nil,
            load: nil,
            tonightBedtime: nil
        )
        XCTAssertTrue(brief.headline.contains("heart data"), brief.headline)
        XCTAssertFalse(brief.headline.contains("baseline"), brief.headline)
        XCTAssertEqual(brief.dataUsed, ["sleep duration"])
    }

    func testAvailableRecoveryStillReadsTheNight() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450)
        let brief = AdaptiveZoonBrief.make(
            phase: .morning,
            night: night,
            recovery: .available(score: 81, confidence: .high),
            energy: nil,
            load: nil,
            tonightBedtime: nil
        )
        XCTAssertTrue(brief.headline.contains("close to your baseline"), brief.headline)
        XCTAssertTrue(brief.dataUsed.contains("Morning Recovery"))
    }

    /// The brief and the ring share one set of cutoffs: 60 is "Moderate" on
    /// the ring, so it cannot be "close to your baseline" here.
    func testBriefUsesTheRingsBands() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 450)
        let brief = AdaptiveZoonBrief.make(
            phase: .morning,
            night: night,
            recovery: .available(score: 60, confidence: .high),
            energy: nil,
            load: nil,
            tonightBedtime: nil
        )
        XCTAssertTrue(brief.headline.contains("mixed"), brief.headline)
    }

    func testRecoveryModeIsOnlySuggestedByAShowableScore() {
        XCTAssertNil(RecoveryMode.evaluate(recovery: .limited(reason: "No HRV."), manuallyEnabledToday: false))
        XCTAssertNil(RecoveryMode.evaluate(recovery: .buildingBaseline(nights: 2, required: 7), manuallyEnabledToday: false))
        XCTAssertNil(RecoveryMode.evaluate(recovery: .unavailable, manuallyEnabledToday: false))
        XCTAssertNil(RecoveryMode.evaluate(recovery: .available(score: 70, confidence: .high), manuallyEnabledToday: false))
        XCTAssertEqual(
            RecoveryMode.evaluate(recovery: .available(score: 20, confidence: .moderate), manuallyEnabledToday: false)?.source,
            .autoSuggested
        )
        XCTAssertEqual(
            RecoveryMode.evaluate(recovery: .limited(reason: "No HRV."), manuallyEnabledToday: true)?.source,
            .manuallyEnabled
        )
    }
}

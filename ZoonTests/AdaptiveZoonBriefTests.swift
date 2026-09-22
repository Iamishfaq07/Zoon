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
}

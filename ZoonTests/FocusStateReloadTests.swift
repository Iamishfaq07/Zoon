import XCTest

/// The Sleep Focus filter writes its flag through its own `UserPreferences`,
/// so the app's long-lived instance has to pick it up rather than keep the
/// value it read at launch -- and a silence must end by itself, because iOS
/// does not reliably tell the filter when a Focus turns off.
@MainActor
final class FocusStateReloadTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "FocusStateReloadTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAFocusThatStartsAfterLaunchIsSeen() {
        let app = UserPreferences(defaults: defaults)
        XCTAssertFalse(app.focusSilencesBedtimeNudges)

        // What `SleepFocusFilter.perform` does when a Focus turns on.
        UserPreferences(defaults: defaults).setFocusSilence(true)
        XCTAssertFalse(app.focusSilencesBedtimeNudges, "still the launch value until reloaded")

        app.reloadFocusState()
        XCTAssertTrue(app.focusSilencesBedtimeNudges)
    }

    func testAFocusThatEndsLetsTheNudgesBack() {
        UserPreferences(defaults: defaults).setFocusSilence(true)
        let app = UserPreferences(defaults: defaults)
        XCTAssertTrue(app.focusSilencesBedtimeNudges)

        UserPreferences(defaults: defaults).setFocusSilence(false)
        app.reloadFocusState()
        XCTAssertFalse(app.focusSilencesBedtimeNudges)
    }

    // MARK: - A silence ends by itself

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    /// iOS calls the filter again with its default ("silence") when the Focus
    /// ends, or not at all. The silence used to last forever after that.
    func testASilenceFromLastNightHasLapsedByThisEvening() {
        XCTAssertTrue(UserPreferences.focusSilenceIsActive(silenced: true, silencedAt: at(27, 22), now: at(28, 7), calendar: calendar))
        XCTAssertFalse(UserPreferences.focusSilenceIsActive(silenced: true, silencedAt: at(27, 22), now: at(28, 21), calendar: calendar))
    }

    func testTheFocusOffCallbackCannotSilenceTheNextEvening() {
        // The default-valued call when the Focus ends at 07:00.
        XCTAssertFalse(UserPreferences.focusSilenceIsActive(silenced: true, silencedAt: at(28, 7), now: at(28, 22), calendar: calendar))
    }

    func testAFlagWithNoStartTimeHasLapsed() {
        XCTAssertFalse(UserPreferences.focusSilenceIsActive(silenced: true, silencedAt: nil, now: at(28, 22), calendar: calendar))
    }

    /// A phone left silenced by the earlier behaviour heals on the next reload.
    func testAStuckFlagIsClearedOnReload() {
        defaults.set(true, forKey: "zoon.pref.focusSilencesBedtimeNudges")
        let app = UserPreferences(defaults: defaults)
        XCTAssertFalse(app.focusSilencesBedtimeNudges)
        app.reloadFocusState()
        XCTAssertFalse(defaults.bool(forKey: "zoon.pref.focusSilencesBedtimeNudges"))
    }
}

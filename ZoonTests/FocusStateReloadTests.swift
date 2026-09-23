import XCTest

/// The Sleep Focus filter writes its flag through its own `UserPreferences`,
/// so the app's long-lived instance has to pick it up rather than keep the
/// value it read at launch.
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
        UserPreferences(defaults: defaults).focusSilencesBedtimeNudges = true
        XCTAssertFalse(app.focusSilencesBedtimeNudges, "still the launch value until reloaded")

        app.reloadFocusState()
        XCTAssertTrue(app.focusSilencesBedtimeNudges)
    }

    func testAFocusThatEndsLetsTheNudgesBack() {
        UserPreferences(defaults: defaults).focusSilencesBedtimeNudges = true
        let app = UserPreferences(defaults: defaults)
        XCTAssertTrue(app.focusSilencesBedtimeNudges)

        UserPreferences(defaults: defaults).focusSilencesBedtimeNudges = false
        app.reloadFocusState()
        XCTAssertFalse(app.focusSilencesBedtimeNudges)
    }
}

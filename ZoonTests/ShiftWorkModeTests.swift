import XCTest

/// Covers Shift Work V2 — the four-mode model that replaced a Bool — and, as
/// much as anything, that replacing it did not quietly change what existing
/// users' phones already believe about their schedule.
@MainActor
final class ShiftWorkModeTests: XCTestCase {

    /// Mirrors `UserPreferences.Key`, which is private. Written literally on
    /// purpose: a migration test has to seed the same key an older build
    /// wrote, and reading the constant back would make the test pass even if
    /// that key changed underneath existing users.
    private let legacyKey = "zoon.pref.shiftWorkModeEnabled"
    private let modeKey = "zoon.pref.shiftWorkMode"

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.zoon.sleep.tests.shift.\(UUID().uuidString)")!
    }

    // MARK: - The model

    /// The Bool inverted the night window, and inverting the night window is
    /// the night-shift case — so `true` has to land on `.night`, not on some
    /// generic "non-standard".
    func testLegacyTrueMigratesToNightShift() {
        XCTAssertEqual(ShiftWorkMode.migrating(fromLegacyEnabled: true), .night)
        XCTAssertEqual(ShiftWorkMode.migrating(fromLegacyEnabled: false), .standard)
    }

    /// Only a standard schedule has a clock-time window Zoon can honestly
    /// apply. Rotating and custom must opt out, which is the whole point of
    /// the V2 model.
    func testOnlyFixedSchedulesUseAClockTimeWindow() {
        XCTAssertTrue(ShiftWorkMode.standard.usesClockTimeWindow)
        XCTAssertTrue(ShiftWorkMode.night.usesClockTimeWindow)
        XCTAssertFalse(ShiftWorkMode.rotating.usesClockTimeWindow)
        XCTAssertFalse(ShiftWorkMode.custom.usesClockTimeWindow)
    }

    func testOnlyStandardTreatsDaytimeAsNap() {
        XCTAssertTrue(ShiftWorkMode.standard.treatsDaytimeAsNap)
        XCTAssertFalse(ShiftWorkMode.night.treatsDaytimeAsNap)
    }

    /// What the widgets and watch app still read across the snapshot boundary.
    func testEveryNonStandardModeReadsAsShiftWorkToTheWidgets() {
        XCTAssertFalse(ShiftWorkMode.standard.isNonStandard)
        for mode in [ShiftWorkMode.night, .rotating, .custom] {
            XCTAssertTrue(mode.isNonStandard, "\(mode) should read as shift work")
        }
    }

    // MARK: - Persistence and migration

    /// An existing user who switched the old toggle on must come back as a
    /// night-shift worker, not be silently reset to standard.
    func testExistingBoolIsMigratedWhenNoModeHasBeenWritten() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: legacyKey)

        let preferences = UserPreferences(defaults: defaults)

        XCTAssertEqual(preferences.shiftWorkMode, .night)
        XCTAssertTrue(preferences.isShiftWorkModeEnabled)
    }

    func testAbsentBoolAndAbsentModeDefaultToStandard() {
        let preferences = UserPreferences(defaults: makeDefaults())

        XCTAssertEqual(preferences.shiftWorkMode, .standard)
        XCTAssertFalse(preferences.isShiftWorkModeEnabled)
    }

    /// Once a mode has been written it wins outright — the stale Bool beside
    /// it must not drag the choice back.
    func testAnExplicitModeBeatsTheLegacyBool() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: legacyKey)
        defaults.set("rotating", forKey: modeKey)

        XCTAssertEqual(UserPreferences(defaults: defaults).shiftWorkMode, .rotating)
    }

    func testModeSurvivesAReload() {
        let defaults = makeDefaults()
        UserPreferences(defaults: defaults).shiftWorkMode = .custom

        XCTAssertEqual(UserPreferences(defaults: defaults).shiftWorkMode, .custom)
    }

    // MARK: - The compatibility setter

    /// The dangerous case. `isShiftWorkModeEnabled` is still writable for
    /// older call sites, and a naive setter mapping `true -> .night` would
    /// quietly demote someone who had chosen `rotating`. It must be a no-op
    /// when the Bool already agrees with the mode.
    func testSettingTheBoolTrueDoesNotDowngradeARotatingSchedule() {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.shiftWorkMode = .rotating

        preferences.isShiftWorkModeEnabled = true

        XCTAssertEqual(preferences.shiftWorkMode, .rotating)
    }

    func testSettingTheBoolFalseReturnsToStandard() {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.shiftWorkMode = .rotating

        preferences.isShiftWorkModeEnabled = false

        XCTAssertEqual(preferences.shiftWorkMode, .standard)
    }

    func testSettingTheBoolTrueFromStandardChoosesNightShift() {
        let preferences = UserPreferences(defaults: makeDefaults())

        preferences.isShiftWorkModeEnabled = true

        XCTAssertEqual(preferences.shiftWorkMode, .night)
    }
}

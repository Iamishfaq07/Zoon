import XCTest

/// A morning start is something the person sets. It used to be on by default
/// at 08:30, so every new install planned around a commitment nobody made:
/// an earlier wake, a later bedtime for early risers, a Monday-to-Friday
/// runway anchored to 08:30.
@MainActor
final class CommitmentDefaultTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.zoon.sleep.tests.commitment-default.\(UUID().uuidString)")!
    }

    func testAFreshInstallHasNoMorningCommitment() {
        let preferences = UserPreferences(defaults: freshDefaults())
        XCTAssertFalse(preferences.tomorrowEventEnabled)
        XCTAssertNil(preferences.manualCommitment)
    }

    func testAnExplicitChoiceSurvivesARelaunch() {
        let defaults = freshDefaults()
        let first = UserPreferences(defaults: defaults)
        first.tomorrowEventEnabled = true
        let relaunched = UserPreferences(defaults: defaults)
        XCTAssertTrue(relaunched.tomorrowEventEnabled)
        XCTAssertNotNil(relaunched.manualCommitment)
    }
}

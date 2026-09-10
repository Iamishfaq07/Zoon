import XCTest

final class SourcePriorityTests: XCTestCase {

    func testHardwareVersionContainingWatchIsPriorityOne() {
        let priority = SourcePriority.classify(
            hardwareVersion: "Watch7,4",
            bundleIdentifier: "com.apple.health",
            sourceName: "Ishfaq’s Apple Watch"
        )
        XCTAssertEqual(priority, .appleWatch)
        XCTAssertEqual(priority.provenanceBonus, 1.0)
    }

    func testIPhoneProductTypeIsNotPromotedToWatch() {
        let priority = SourcePriority.classify(
            hardwareVersion: "iPhone15,2",
            bundleIdentifier: "com.apple.health",
            sourceName: "iPhone"
        )
        XCTAssertEqual(priority, .phoneOrManual)
        XCTAssertEqual(priority.provenanceBonus, 0)
    }

    func testRecognisedWearableIsPriorityTwo() {
        let priority = SourcePriority.classify(
            hardwareVersion: nil,
            bundleIdentifier: "com.garmin.connect",
            sourceName: "Garmin Connect"
        )
        XCTAssertEqual(priority, .thirdPartyWearable)
        XCTAssertGreaterThan(priority.provenanceBonus, 0)
        XCTAssertLessThan(priority.provenanceBonus, SourcePriority.appleWatch.provenanceBonus)
    }

    func testManualAndUnknownArePriorityThree() {
        let priority = SourcePriority.classify(
            hardwareVersion: nil,
            bundleIdentifier: "com.example.sleepdiary",
            sourceName: "Sleep Diary"
        )
        XCTAssertEqual(priority, .phoneOrManual)
    }

    /// A third-party app running on the Watch reports Watch hardware too. It
    /// is still a third-party writer, not Apple's own sleep staging.
    func testThirdPartyAppOnWatchHardwareIsNotPromotedToAppleWatch() {
        let priority = SourcePriority.classify(
            hardwareVersion: "Watch7,4",
            bundleIdentifier: "com.tantsissa.AutoSleep",
            sourceName: "AutoSleep"
        )
        XCTAssertEqual(priority, .thirdPartyWearable)
    }

    func testWatchOutranksWearableWhichOutranksPhone() {
        XCTAssertLessThan(SourcePriority.appleWatch, SourcePriority.thirdPartyWearable)
        XCTAssertLessThan(SourcePriority.thirdPartyWearable, SourcePriority.phoneOrManual)
    }
}

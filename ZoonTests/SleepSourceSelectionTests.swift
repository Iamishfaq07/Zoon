import XCTest

/// Both source pickers list every writer, winning or not.
final class SleepSourceSelectionTests: XCTestCase {

    /// A second tracker that wrote every night but never beat the Watch has
    /// no stored night, and used to be missing from the picker.
    func testAWriterThatNeverWonIsListed() {
        let merged = SleepSourceList.merged(
            stored: [(name: "Apple Watch", bundleIdentifier: "com.apple.health.A")],
            writers: [
                (name: "Apple Watch", bundleIdentifier: "com.apple.health.A"),
                (name: "Ring Tracker", bundleIdentifier: "com.example.ring"),
            ]
        )
        XCTAssertEqual(merged.map(\.name), ["Apple Watch", "Ring Tracker"])
        XCTAssertEqual(merged.last?.bundleIdentifier, "com.example.ring")
    }

    /// A stored row from before the identifier column is filled from the
    /// writer list rather than staying name-only.
    func testAWriterFillsAMissingIdentifier() {
        let merged = SleepSourceList.merged(
            stored: [(name: "Pillow", bundleIdentifier: nil)],
            writers: [(name: "Pillow", bundleIdentifier: "com.example.pillow")]
        )
        XCTAssertEqual(merged.first?.bundleIdentifier, "com.example.pillow")
    }
}

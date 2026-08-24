import XCTest

/// Black-box smoke tests, driving the real app process via the accessibility
/// tree -- the one thing `ZoonTests` (a standalone logic bundle with no host
/// app) structurally cannot exercise: does the app actually launch and put a
/// tab bar on screen.
///
/// Deliberately minimal. `-zoonDemo YES` (see `LaunchOptions`) forces the
/// mock dataset so this runs deterministically in CI with no HealthKit
/// permission sheet and no dependency on the runner ever having real sleep
/// data.
final class ZoonUITests: XCTestCase {

    func testLaunchesToTabBar() {
        let app = XCUIApplication()
        app.launchArguments += ["-zoonDemo", "YES"]
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }
}

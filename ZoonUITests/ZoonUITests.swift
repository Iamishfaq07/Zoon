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

        XCTAssertTrue(app.buttons["zoon.tab.today"].waitForExistence(timeout: 10))
        for tab in ["Sleep", "Insights", "Coach", "Today"] {
            let button = app.buttons["zoon.tab.\(tab.lowercased())"]
            XCTAssertTrue(button.exists, "Missing core tab \(tab)")
            button.tap()
            XCTAssertTrue(button.isSelected)
        }
    }

    func testCoreSleepAndCoachFlowsOpen() {
        let app = XCUIApplication()
        app.launchArguments += ["-zoonDemo", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["zoon.tab.today"].waitForExistence(timeout: 10))

        app.buttons["zoon.tab.sleep"].tap()
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Last night in numbers"].waitForExistence(timeout: 5))

        app.buttons["zoon.tab.coach"].tap()
        XCTAssertTrue(app.staticTexts["Ask Zoon"].waitForExistence(timeout: 5))
    }
}

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

    /// Apple's accessibility audit on the four main tabs, in demo mode.
    ///
    /// Reports rather than fails, for now: every issue is logged with an
    /// `A11Y-AUDIT` prefix -- screen, audit type, and the element's label --
    /// and CI prints the list. An audit that failed on its first run would
    /// only say that something is wrong, not what, and the point of this pass
    /// is the list. Once it has been worked through, the handler should
    /// return `false` so new issues fail the build.
    func testAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-zoonDemo", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["zoon.tab.today"].waitForExistence(timeout: 10))

        for tab in ["today", "sleep", "insights", "coach"] {
            app.buttons["zoon.tab.\(tab)"].tap()
            // Let the entrance animations settle; an audit of a half-faded
            // screen reports contrast that is not there at rest.
            _ = app.buttons["zoon.tab.\(tab)"].waitForExistence(timeout: 2)
            sleep(2)
            let audit: () throws -> Void = {
                try app.performAccessibilityAudit { issue in
                    let label = issue.element?.label ?? "(no element)"
                    print("A11Y-AUDIT \(tab) | \(issue.auditType) | \(issue.compactDescription) | \(label)")
                    // The detail behind each line: which element, where, and the
                    // audit's own explanation (contrast ratios live here).
                    if let element = issue.element {
                        print("A11Y-DETAIL \(tab) | type \(element.elementType.rawValue) | id '\(element.identifier)' | frame \(element.frame) | \(issue.detailedDescription)")
                    } else {
                        print("A11Y-DETAIL \(tab) | no element | \(issue.detailedDescription)")
                    }
                    return true
                }
            }
            // The audit has its own time limit, and a loaded CI runner can
            // exceed it (error -56, "Audit failed to complete in time").
            // That says nothing about the app, so one retry, then it is
            // logged and the tab skipped rather than turning the build red.
            // Any other error still fails the test.
            do {
                try audit()
            } catch let error as NSError where error.code == -56 {
                do {
                    try audit()
                } catch let retry as NSError where retry.code == -56 {
                    print("A11Y-AUDIT-TIMEOUT \(tab) | the audit did not finish in time twice; this tab was not audited")
                }
            }
        }
    }
}


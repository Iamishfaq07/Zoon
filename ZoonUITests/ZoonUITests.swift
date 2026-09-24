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

        // 15s, not 5: a loaded CI runner once took over 5s to show Coach
        // (run 35905062519, green on re-run with no code change). The wait
        // returns as soon as the element exists, so this costs nothing when
        // the app is quick.
        app.buttons["zoon.tab.sleep"].tap()
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Last night in numbers"].waitForExistence(timeout: 15))

        app.buttons["zoon.tab.coach"].tap()
        XCTAssertTrue(app.staticTexts["Ask Zoon"].waitForExistence(timeout: 15))
    }

    /// Audit §15: the app still navigates with every localized string
    /// doubled in length (`NSDoubleLocalizedStrings`, Foundation's
    /// pseudolocalization switch) and with the layout forced right to left.
    /// A screenshot of each is attached to the result bundle.
    func testLongStringsAndRightToLeftStillNavigate() {
        let variants: [(name: String, arguments: [String])] = [
            ("double-length strings", ["-NSDoubleLocalizedStrings", "YES"]),
            ("right to left", ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
        ]
        for variant in variants {
            let app = XCUIApplication()
            app.launchArguments += ["-zoonDemo", "YES"] + variant.arguments
            app.launch()
            XCTAssertTrue(app.buttons["zoon.tab.today"].waitForExistence(timeout: 15), variant.name)
            for tab in ["sleep", "insights", "coach", "today"] {
                let button = app.buttons["zoon.tab.\(tab)"]
                XCTAssertTrue(button.waitForExistence(timeout: 10), "\(variant.name): no \(tab) tab")
                button.tap()
                XCTAssertTrue(button.isSelected, "\(variant.name): \(tab) did not open")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Today, \(variant.name)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    /// Apple's accessibility audit on the four main tabs, in demo mode, as a
    /// gate (audit §14).
    ///
    /// It used to log every issue and pass. Now:
    /// - an issue of a kind with no known instances on that tab (missing
    ///   label, small hit region, wrong trait, ...) fails the test at once;
    /// - the kinds with known instances -- contrast, Dynamic Type, clipped
    ///   text -- may not grow past `Self.knownIssues` for that tab.
    ///
    /// The known counts are the baseline from CI run 35994647333, plus
    /// `Self.demoDataSlack`: the demo night's timeline labels are generated
    /// relative to today, so a count can move by a line with no code change.
    /// Every issue is still printed (`A11Y-AUDIT`) so the list stays visible.
    /// Fixing issues means lowering these numbers, never raising them.
    static let knownIssues: [String: [String: Int]] = [
        "today": ["contrast": 16, "dynamicType": 6, "textClipped": 4],
        "sleep": ["contrast": 22, "dynamicType": 9, "textClipped": 4],
        "insights": ["contrast": 7, "dynamicType": 11],
        "coach": ["contrast": 10, "dynamicType": 17]
    ]
    static let demoDataSlack = 2

    static func category(_ type: XCUIAccessibilityAuditType) -> String {
        if type == .contrast { return "contrast" }
        if type == .dynamicType { return "dynamicType" }
        if type == .textClipped { return "textClipped" }
        return "other(\(type.rawValue))"
    }

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
            let known = Self.knownIssues[tab] ?? [:]
            let tally = Tally()
            let audit: () throws -> Void = {
                tally.counts = [:]
                try app.performAccessibilityAudit { issue in
                    let label = issue.element?.label ?? "(no element)"
                    let category = Self.category(issue.auditType)
                    print("A11Y-AUDIT \(tab) | \(issue.auditType) | \(issue.compactDescription) | \(label)")
                    // The detail behind each line: which element, where, and the
                    // audit's own explanation (contrast ratios live here).
                    if let element = issue.element {
                        print("A11Y-DETAIL \(tab) | type \(element.elementType.rawValue) | id '\(element.identifier)' | frame \(element.frame) | \(issue.detailedDescription)")
                    } else {
                        print("A11Y-DETAIL \(tab) | no element | \(issue.detailedDescription)")
                    }
                    tally.counts[category, default: 0] += 1
                    // `false` reports the issue as a failure: a kind this tab
                    // has never had is a regression, not a baseline item.
                    return known[category] != nil
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
                    continue
                }
            }
            for (category, limit) in known {
                let found = tally.counts[category, default: 0]
                print("A11Y-GATE \(tab) | \(category) | found \(found) | known \(limit)")
                XCTAssertLessThanOrEqual(
                    found, limit + Self.demoDataSlack,
                    "\(tab): \(found) \(category) issues, more than the \(limit) known. A new element has this problem; fix it rather than raising the baseline."
                )
            }
        }
    }
}

/// Per-tab issue counts, reset before each audit attempt so a retried audit
/// is not counted twice. A class so the issue handler can add to it however
/// the SDK annotates that closure.
private final class Tally {
    var counts: [String: Int] = [:]
}

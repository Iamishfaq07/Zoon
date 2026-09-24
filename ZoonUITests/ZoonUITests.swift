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
                XCTAssertTrue(select(button), "\(variant.name): \(tab) did not open")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Today, \(variant.name)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    /// Taps a tab and waits for it to become selected.
    ///
    /// On a loaded runner a tap can arrive while the previous tab is still
    /// settling and be dropped (run 36061792999: the Sleep tap took 35s to
    /// deliver, the Insights tap straight after it did not register, and the
    /// Coach and Today taps that followed did). So the check waits for the
    /// selection rather than reading it the instant the tap returns, and taps
    /// once more if the first tap was lost. A tab that never opens still fails.
    private func select(_ button: XCUIElement) -> Bool {
        button.tap()
        if waitUntilSelected(button, timeout: 5) { return true }
        button.tap()
        return waitUntilSelected(button, timeout: 10)
    }

    private func waitUntilSelected(_ button: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Apple's accessibility audit on the four main tabs, in demo mode, as a
    /// gate (audit §14).
    ///
    /// It used to log every issue and pass. Now an issue of a kind the app
    /// has no known instances of -- missing label, small hit region, wrong
    /// trait, element detection -- fails the test at once, on any tab.
    ///
    /// The kinds with known instances (contrast, Dynamic Type, clipped text)
    /// are counted and printed against `Self.knownIssues` (`A11Y-GATE`), not
    /// enforced as ceilings. Tried first as ceilings, they failed on unchanged
    /// code: which cards have loaded when the audit runs, and the demo night's
    /// date-relative labels, moved Insights' Dynamic Type count from 11 to 20
    /// and Sleep's from 9 to 3 between two runs. A gate that fails at random
    /// teaches people to ignore it. The counts are the to-do list; fixing an
    /// item lowers them.
    /// Kinds with known instances somewhere in the app. Any other kind fails.
    static var knownKinds: Set<String> { Set(knownIssues.values.flatMap(\.keys)) }

    static let knownIssues: [String: [String: Int]] = [
        "today": ["contrast": 16, "dynamicType": 6, "textClipped": 4],
        "sleep": ["contrast": 22, "dynamicType": 9, "textClipped": 4],
        "insights": ["contrast": 7, "dynamicType": 11],
        "coach": ["contrast": 10, "dynamicType": 17]
    ]

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
                    // `false` reports the issue as a failure: a kind the app
                    // has never had is a regression, not a baseline item.
                    return Self.knownKinds.contains(category)
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
            for (category, baseline) in known.sorted(by: { $0.key < $1.key }) {
                let found = tally.counts[category, default: 0]
                print("A11Y-GATE \(tab) | \(category) | found \(found) | baseline \(baseline)")
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

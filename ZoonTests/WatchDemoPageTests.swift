import XCTest

/// Every page the capture can ask for must actually be in the deck.
///
/// The watch's `TabView` cannot select a tag that is not present and falls
/// back silently rather than failing, so a pinned page that does not exist
/// photographs whatever was showing and files it under the name that was
/// asked for. Three renders were published that way before this was noticed:
/// Tonight, Nap and Score-light were all pictures of Last Night.
///
/// The capture compares each page render against the fallback and drops a
/// match, but that check is weaker than it looks -- the watch status bar
/// carries a live clock, so two captures of the same page differ whenever the
/// minute rolls over between them. It catches the obvious case and cannot be
/// relied on for the rest.
///
/// This is the guarantee that does not depend on pixels: for every page, the
/// demo snapshot chosen for it satisfies the condition `WatchRootView` puts
/// that page behind.
final class WatchDemoPageTests: XCTestCase {

    private func snapshot(_ page: String) -> SleepSnapshot {
        WatchLink.demoSnapshot(forPage: page)
    }

    /// `if snapshot.isNapRunning()`
    func testNapPageHasARunningNap() {
        XCTAssertTrue(snapshot("nap").isNapRunning(), "the Nap page would not be in the deck")
    }

    /// A timer photographed at four seconds proves nothing about how it
    /// reads, so the nap is mid-flight rather than nearly over.
    func testTheDemoNapIsMidFlight() {
        let napping = snapshot("nap")
        let remaining = napping.napTargetEnd!.timeIntervalSinceNow / 60
        XCTAssertGreaterThan(remaining, 10, "too close to the end to photograph")
        XCTAssertLessThan(remaining, 60, "implausibly long for a nap")
    }

    /// `if snapshot.scoreLightMode`
    func testScoreLightPageHasTheModeOn() {
        XCTAssertTrue(snapshot("scoreLight").scoreLightMode, "the Score-light page would not be in the deck")
    }

    /// `if hasTonight(snapshot)` -- gated on the target label being non-empty,
    /// because a page rendering a blank target is worse than one page fewer.
    func testTonightPageHasAPlan() {
        XCTAssertFalse(
            snapshot("tonight").tonightTargetLabel.isEmpty,
            "the Tonight page would not be in the deck"
        )
    }

    /// The other half of score-light: when it is on, Last Night and Today are
    /// replaced rather than joined. Asking for either must therefore get a
    /// snapshot with the mode *off*, or the page asked for is the one page
    /// guaranteed absent.
    func testLastNightAndTodayGetTheModeOff() {
        for page in ["lastNight", "today"] {
            XCTAssertFalse(
                snapshot(page).scoreLightMode,
                "\(page) is replaced by Score-light when the mode is on"
            )
        }
    }

    /// Case is not meaningful in a launch argument somebody types by hand.
    func testThePageArgumentIgnoresCase() {
        XCTAssertTrue(snapshot("SCORELIGHT").scoreLightMode)
        XCTAssertTrue(snapshot("nap").isNapRunning())
        XCTAssertTrue(snapshot("NAP").isNapRunning())
    }

    /// An unknown or absent argument still yields a usable snapshot rather
    /// than nothing -- the ordinary demo, which is what the size sweep shoots.
    func testAnUnknownPageStillGetsTheOrdinaryDemo() {
        for page in [nil, "", "nonsense"] {
            let s = WatchLink.demoSnapshot(forPage: page)
            XCTAssertTrue(s.canStateRecovery, "\(String(describing: page)) gave an empty demo")
            XCTAssertFalse(s.scoreLightMode)
        }
    }

    /// The pages with no condition at all, asserted so that a future gate
    /// added to either is caught here rather than in a render.
    func testMoreAndLogAreUnconditional() {
        for page in ["more", "log"] {
            XCTAssertNotNil(WatchLink.demoSnapshot(forPage: page))
        }
    }
}

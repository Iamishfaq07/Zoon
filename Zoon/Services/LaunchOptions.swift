import Foundation

/// Launch-time overrides, read from the process arguments.
///
/// These exist for one reason: capturing screenshots of the app on a CI
/// runner, where nobody can tap a permission sheet and no real sleep data
/// exists. `xcrun simctl launch` passes trailing arguments to the app, and
/// `UserDefaults.standard` already parses `-key value` pairs out of `argv`, so
/// no argument parsing is needed here.
///
/// ```
/// xcrun simctl launch booted com.zoon.sleep -zoonDemo YES -zoonTab trends
/// ```
///
/// Nothing here changes behaviour on a normal launch: with no arguments,
/// `isDemo` is `false` and `initialTab` is `nil`. The keys are prefixed so a
/// stray global default can't switch them on by accident.
enum LaunchOptions {

    /// Force the mock dataset and skip HealthKit entirely.
    ///
    /// The Simulator *does* have a Health store — `isHealthDataAvailable()`
    /// returns true there — so the ordinary "no Health, use mock data" path
    /// doesn't trigger, and the app would sit on an authorization sheet
    /// forever. This bypasses that.
    ///
    /// Mock nights are badged **Sample data** wherever they appear, so a demo
    /// screenshot can never be mistaken for a measured one.
    static var isDemo: Bool {
        UserDefaults.standard.bool(forKey: "zoonDemo")
    }

    /// Which tab to open on. One of `today`, `sleep`, `trends`, `journal`,
    /// `more`; anything else is ignored.
    ///
    /// Screenshot capture relaunches the app once per tab rather than driving
    /// the tab bar, which avoids needing a UI-test target — and a UI test would
    /// mean a third target in the project file, which is the part of this repo
    /// that has broken most often.
    static var initialTab: String? {
        UserDefaults.standard.string(forKey: "zoonTab")
    }
}

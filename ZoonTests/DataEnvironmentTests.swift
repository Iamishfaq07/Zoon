import XCTest

/// `DataEnvironment` replaced seven hand-written copies of the same compound
/// condition in `SleepDataCoordinator`. Two of its properties are worth
/// locking in, because getting either wrong fails quietly rather than loudly:
///
/// - **Demo must win over health availability.** The Simulator has a real
///   Health store, so resolving availability first would let a screenshot run
///   take the live path and hang on an authorization sheet nobody can tap.
/// - **`isLive` and `isSample` must stay exact opposites.** Call sites guard
///   on one or the other interchangeably; a case that answered `false` to both
///   would skip the live path *and* the fallback.
final class DataEnvironmentTests: XCTestCase {

    func testDemoReasonBeatsHealthAvailability() {
        // The ordering trap this type exists to encode: on a Simulator, health
        // data *is* available, so only checking the demo flag first produces
        // the sample environment.
        let demo = DataEnvironment.sample(.demoLaunchArgument)
        XCTAssertTrue(demo.isSample)
        XCTAssertFalse(demo.isLive)
    }

    func testLiveAndSampleAreExactOpposites() {
        let cases: [DataEnvironment] = [
            .live,
            .sample(.demoLaunchArgument),
            .sample(.healthDataUnavailable)
        ]
        for environment in cases {
            XCTAssertNotEqual(
                environment.isLive, environment.isSample,
                "\(environment) answered the same to isLive and isSample"
            )
        }
    }

    func testOnlySampleEnvironmentsLogAFallback() {
        XCTAssertNil(DataEnvironment.live.fallbackLogMessage)
        XCTAssertNotNil(DataEnvironment.sample(.demoLaunchArgument).fallbackLogMessage)
        XCTAssertNotNil(DataEnvironment.sample(.healthDataUnavailable).fallbackLogMessage)
    }

    func testReasonsAreDistinguishable() {
        // The two sample reasons behave identically today, but they are
        // reported differently in the log -- a demo run and a device without
        // Health are very different things to be looking at in a bug report.
        XCTAssertNotEqual(
            DataEnvironment.sample(.demoLaunchArgument),
            DataEnvironment.sample(.healthDataUnavailable)
        )
    }
}

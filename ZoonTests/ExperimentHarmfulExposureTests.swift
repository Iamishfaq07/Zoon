import XCTest

/// A controlled design assigns nights *with* the behaviour. For alcohol,
/// nicotine, cannabis, caffeine and sleep aids that would be Zoon scheduling
/// a week of drinking or of a sleep aid (App Review guideline 1.4.3), so those
/// may only ever be tested as a before-and-after of cutting back -- however
/// the trial is started, restored, or left over from an earlier build.
@MainActor
final class ExperimentHarmfulExposureTests: XCTestCase {

    private let harmful: [BehaviorTag] = [.alcohol, .nicotine, .cannabis, .caffeine, .caffeineLate, .sleepAid]

    private func makePreferences() -> UserPreferences {
        UserPreferences(defaults: UserDefaults(suiteName: "com.zoon.sleep.tests.exposure.\(UUID().uuidString)")!)
    }

    func testHarmfulBehavioursAllowOnlyBeforeAndAfter() {
        for tag in harmful {
            XCTAssertEqual(ExperimentDesign.allowed(for: tag), [.beforeAfter], "\(tag)")
            for design in ExperimentDesign.allCases {
                XCTAssertEqual(design.permitted(for: tag), .beforeAfter, "\(tag) \(design)")
            }
        }
    }

    func testOrdinaryChoicesKeepEveryDesign() {
        XCTAssertEqual(ExperimentDesign.allowed(for: .screenBeforeBed), ExperimentDesign.allCases)
        XCTAssertEqual(ExperimentDesign.abba.permitted(for: .coolRoom), .abba)
    }

    func testStartingACrossoverOnAHarmfulBehaviourSchedulesNothing() {
        for tag in harmful {
            let preferences = makePreferences()
            preferences.startExperiment(tag, direction: .avoid, design: .abba, seed: 7)
            XCTAssertEqual(preferences.experimentDesign, .beforeAfter, "\(tag)")
            XCTAssertTrue(preferences.experimentSchedule.isEmpty, "\(tag) must never get a with/without plan")
        }
    }

    func testARestoredCrossoverOnAHarmfulBehaviourIsBeforeAndAfter() {
        let preferences = makePreferences()
        preferences.restoreActiveExperiment(
            tag: .sleepAid, startDate: .now, hypothesis: nil, primaryMetric: nil,
            direction: .avoid, design: .ba, seed: 3
        )
        XCTAssertEqual(preferences.experimentDesign, .beforeAfter)
        XCTAssertTrue(preferences.experimentSchedule.isEmpty)
    }

    func testAnOrdinaryCrossoverStillGetsItsPlan() {
        let preferences = makePreferences()
        preferences.startExperiment(.screenBeforeBed, direction: .avoid, design: .abba, seed: 7)
        XCTAssertEqual(preferences.experimentDesign, .abba)
        XCTAssertEqual(preferences.experimentSchedule.count, ExperimentDesign.abba.plannedNights())
        XCTAssertTrue(preferences.experimentSchedule.contains { $0.arm == .with })
    }
}

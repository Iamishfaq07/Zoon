import XCTest

/// One rule for "awakening", and the fixture that used to give three answers.
final class AwakeningPolicyTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    /// A 30-second flicker, a two-and-a-half-minute wake, and a two-minute
    /// stretch before getting up, with in-bed time either end.
    private var fixture: [StageSegment] {
        [
            StageSegment(stage: .inBed, start: at(0), end: at(10)),
            StageSegment(stage: .core, start: at(10), end: at(100)),
            StageSegment(stage: .awake, start: at(100), end: at(100.5)),
            StageSegment(stage: .deep, start: at(100.5), end: at(200)),
            StageSegment(stage: .awake, start: at(200), end: at(202.5)),
            StageSegment(stage: .rem, start: at(202.5), end: at(420)),
            StageSegment(stage: .awake, start: at(420), end: at(422)),
            StageSegment(stage: .inBed, start: at(422), end: at(430)),
        ]
    }

    func testTheFixtureHasOneAwakening() {
        let episodes = AwakeningPolicy.episodes(in: fixture)
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.start, at(200))
    }

    /// In-bed time after onset is not an observed wake.
    func testInBedIsNotAnAwakening() {
        let segments = [
            StageSegment(stage: .core, start: at(0), end: at(100)),
            StageSegment(stage: .inBed, start: at(100), end: at(110)),
            StageSegment(stage: .core, start: at(110), end: at(300)),
        ]
        XCTAssertTrue(AwakeningPolicy.episodes(in: segments).isEmpty)
    }

    /// The story and the policy name the same awakenings.
    func testTheStoryUsesTheSameRule() {
        var night = Fixture.night(daysAgo: 1)
        night.stageSegments = fixture
        let story = SleepStory.build(night: night)
        XCTAssertEqual(story.events.filter { $0.title == "Woke briefly" }.count, 1)
    }

    /// And the stored count's threshold is the same number.
    func testTheBuilderThresholdIsThePolicy() {
        XCTAssertEqual(SleepSession.meaningfulAwakeningThreshold, AwakeningPolicy.minimumDuration)
    }
}

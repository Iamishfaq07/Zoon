import XCTest
import SwiftData
import HealthKit

/// Service-level coverage of the path a night actually takes:
///
/// ```text
/// HKCategorySample -> SleepSessionBuilder -> SleepNightFeatures
///   -> SleepHistoryStore (in-memory SwiftData) -> historicalFeatures
///   -> analytics
/// ```
///
/// V8 Task 7 asks for exactly this: correctness checked where the pieces meet,
/// not only inside isolated pure functions. Most of Zoon's suite tests one
/// algorithm against hand-written input; nothing until now carried real
/// builder output all the way into persistence and back out through the
/// analytics that read it.
///
/// ## What this deliberately does not cover
///
/// The vitals half of a night — heart rate, HRV, respiratory rate, wrist
/// temperature — comes from `FeatureExtractor.extract(from:baseline:)`, which
/// is `async` and reads `HealthKitManager` directly. There is no
/// `HealthDataProviding` protocol to substitute a mock for, so that half of
/// the pipeline cannot be reached from a test bundle at all. Extracting that
/// seam is a refactor of the app's core data path and is tracked separately;
/// pretending these tests cover it would be worse than the gap.
///
/// Likewise: this is a Simulator unit-test bundle. Nothing here has been
/// verified against real HealthKit data on a real device.
@MainActor
final class IntegrationFlowTests: XCTestCase {

    /// Retained for the lifetime of the test. A `ModelContainer` released
    /// while a store still holds its `mainContext` traps inside SwiftData and
    /// takes the whole test process down with no XCTest failure message —
    /// see `SleepHistoryStoreIntegrationTests` for the full post-mortem.
    private var container: ModelContainer?

    private let calendar = Calendar.current

    private func makeStore() throws -> SleepHistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SleepNightRecord.self, SleepEpisodeRecord.self,
            configurations: config
        )
        self.container = container
        return SleepHistoryStore(context: container.mainContext)
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour))!
    }

    private func sample(
        _ stage: HKCategoryValueSleepAnalysis,
        _ start: Date,
        _ end: Date
    ) -> HKCategorySample {
        HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: stage.rawValue,
            start: start,
            end: end
        )
    }

    /// Two ordinary nights, each staged.
    private func twoNightsOfSamples() -> [HKCategorySample] {
        [
            sample(.asleepCore, date(1, 23), date(2, 3)),
            sample(.asleepDeep, date(2, 3), date(2, 5)),
            sample(.asleepREM, date(2, 5), date(2, 7)),

            sample(.asleepCore, date(2, 23), date(3, 4)),
            sample(.asleepDeep, date(3, 4), date(3, 5)),
            sample(.asleepREM, date(3, 5), date(3, 7))
        ]
    }

    // MARK: - Samples through to persistence

    func testTwoNightsOfSamplesBecomeTwoPersistedNights() throws {
        let store = try makeStore()
        let sessions = SleepSessionBuilder().buildSessions(from: twoNightsOfSamples())

        XCTAssertEqual(sessions.count, 2, "The builder should see two distinct nights.")

        for session in sessions {
            let features = Fixture.night(from: session, need: 480)
            _ = store.upsert(features, nightKey: features.nightKey)
        }

        XCTAssertEqual(store.allNights().count, 2)
    }

    /// Re-processing the same samples — an incremental sync re-reading a night
    /// it already has — must update in place, not accumulate duplicates.
    func testReprocessingTheSameSamplesDoesNotDuplicateNights() throws {
        let store = try makeStore()
        let samples = twoNightsOfSamples()

        for _ in 0..<3 {
            for session in SleepSessionBuilder().buildSessions(from: samples) {
                let features = Fixture.night(from: session, need: 480)
                _ = store.upsert(features, nightKey: features.nightKey)
            }
        }

        XCTAssertEqual(store.allNights().count, 2, "Three passes, still two nights.")
    }

    /// Night identity has to survive the store round trip, or a journal entry
    /// or behaviour answer written against that key silently detaches.
    func testNightKeySurvivesPersistence() throws {
        let store = try makeStore()
        let session = try XCTUnwrap(
            SleepSessionBuilder().buildSessions(from: twoNightsOfSamples()).first
        )
        let features = Fixture.night(from: session, need: 480)

        _ = store.upsert(features, nightKey: features.nightKey)

        let stored = try XCTUnwrap(store.allNights().first)
        XCTAssertEqual(stored.nightKey, features.nightKey)
        XCTAssertFalse(features.nightKey.isEmpty)
    }

    // MARK: - Persistence through to analytics

    /// The far end of the pipeline: what comes back out must be usable by the
    /// analytics that read it, with the sleep totals intact.
    func testPersistedNightsReadBackWithTheirDurationsIntact() throws {
        let store = try makeStore()
        let sessions = SleepSessionBuilder().buildSessions(from: twoNightsOfSamples())
        let expected = sessions.map { Fixture.night(from: $0, need: 480).timeAsleepMinutes }

        for session in sessions {
            let features = Fixture.night(from: session, need: 480)
            _ = store.upsert(features, nightKey: features.nightKey)
        }

        let readBack = store.historicalFeatures(goalMinutes: 480)

        XCTAssertEqual(readBack.count, 2)
        assertEqual(
            readBack.map(\.timeAsleepMinutes).sorted(),
            expected.sorted(),
            accuracy: 0.5
        )
    }

    /// Sufficiency computed from stored nights, end to end — the question the
    /// whole pipeline exists to answer.
    func testSufficiencyIsComputableFromStoredNights() throws {
        let store = try makeStore()
        for session in SleepSessionBuilder().buildSessions(from: twoNightsOfSamples()) {
            let features = Fixture.night(from: session, need: 480)
            _ = store.upsert(features, nightKey: features.nightKey)
        }

        let nights = store.historicalFeatures(goalMinutes: 480)
        let sufficiency = SleepSufficiencyEngine.averagePercent(nights: nights, goalMinutes: 480)

        let value = try XCTUnwrap(sufficiency)
        XCTAssertTrue(value.isFinite)
        XCTAssertTrue((0...100).contains(value), "Got \(value)")
    }

    /// An empty store must produce "nothing to say", not a confident zero.
    func testAnEmptyStoreYieldsNoSufficiencyRatherThanZero() throws {
        let store = try makeStore()

        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(
            SleepSufficiencyEngine.averagePercent(
                nights: store.historicalFeatures(goalMinutes: 480),
                goalMinutes: 480
            )
        )
    }

    // MARK: - The source bridge, end to end

    /// Task 6's defect, checked through the real pipeline rather than at the
    /// scoring seam: a malformed 20-hour block must not collapse two nights
    /// into one persisted row.
    ///
    /// In this bundle every sample reports the same source (there is no API to
    /// set `sourceRevision` on an unsaved sample), so the bad block is treated
    /// as same-source data — which is the *harder* case for the builder, not
    /// an easier one: same-source samples are clustered together by gap, so
    /// nothing separates them but the pipeline's own handling.
    func testAMalformedBlockDoesNotSilentlyCollapseTwoNightsIntoOne() throws {
        let store = try makeStore()
        var samples = twoNightsOfSamples()
        samples.append(sample(.asleepUnspecified, date(2, 6), date(3, 2)))

        for session in SleepSessionBuilder().buildSessions(from: samples) {
            let features = Fixture.night(from: session, need: 480)
            _ = store.upsert(features, nightKey: features.nightKey)
        }

        // Whatever the merge produces, no persisted night may claim a
        // physically impossible amount of sleep.
        for night in store.historicalFeatures(goalMinutes: 480) {
            XCTAssertLessThanOrEqual(
                night.timeAsleepMinutes, 16 * 60,
                "A persisted night claiming more than 16h of sleep is a bridge, not a night."
            )
        }
    }
}

/// Element-wise comparison with tolerance. Named distinctly rather than
/// overloading `XCTAssertEqual`, which risks ambiguous resolution against
/// XCTest's own generic collection overloads.
private func assertEqual(
    _ lhs: [Double],
    _ rhs: [Double],
    accuracy: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
    for (a, b) in zip(lhs, rhs) {
        XCTAssertEqual(a, b, accuracy: accuracy, file: file, line: line)
    }
}

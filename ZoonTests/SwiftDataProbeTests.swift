import XCTest
import SwiftData

/// Diagnostic probe, not a real feature test.
///
/// `ZoonTests` has never successfully run a SwiftData `ModelContainer`
/// against real model types -- every prior attempt (`SleepHistoryStorePruneTests`,
/// dropped in commit "Drop SleepHistoryStorePruneTests -- crashes the test
/// process, cause unknown") crashed the whole test process with zero
/// diagnostic output, not a clean assertion failure. That attempt pulled in
/// `SleepHistoryStore`/`FeatureExtractor`/`HealthKitManager` as well, so it
/// couldn't distinguish "SwiftData itself can't run in this unhosted test
/// bundle" from "something specific to that store's code crashes."
///
/// This narrows the surface to the smallest possible reproduction: one
/// `@Model` type with no dependencies beyond Foundation+SwiftData
/// (`SleepNightRecord`), no store wrapper, nothing but `ModelContainer`
/// construction, an insert, and a fetch. If this alone still crashes, the
/// problem is SwiftData/this bundle's hosting configuration, not any
/// particular store. If it passes, the earlier crash was specific to
/// something `SleepHistoryStore`/`FeatureExtractor`/`HealthKitManager`
/// pulled in, and that combination can be re-tried piece by piece.
///
/// The CI workflow now also captures `~/Library/Logs/DiagnosticReports/*.ips`
/// as a build artifact (see `.github/workflows/build.yml`) -- if this still
/// crashes, that artifact should finally carry the actual signal/stack trace
/// the previous two attempts never got to see.
@MainActor
final class SwiftDataProbeTests: XCTestCase {

    func testInMemoryModelContainerCanInsertAndFetchOneRecord() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SleepNightRecord.self, configurations: config)
        let context = container.mainContext

        let record = SleepNightRecord(features: Fixture.night())
        context.insert(record)
        try context.save()

        let descriptor = FetchDescriptor<SleepNightRecord>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
    }

    /// Narrows the surface one more notch. The test above (no predicate)
    /// passes; every store method that crashed
    /// (`JournalStore.entry(for:)`, `SleepHistoryStore.prune`, ...) fetches
    /// through a `#Predicate` instead, which is the one SwiftData feature
    /// the passing probe never touched. If this crashes and the one above
    /// doesn't, `#Predicate` evaluation -- not SwiftData generally -- is
    /// what this test bundle can't do, and the stores need predicate-free
    /// fetch paths to be testable here.
    func testInMemoryModelContainerCanFetchThroughAPredicate() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SleepNightRecord.self, configurations: config)
        let context = container.mainContext

        let record = SleepNightRecord(features: Fixture.night())
        let target = record.date
        context.insert(record)
        try context.save()

        let descriptor = FetchDescriptor<SleepNightRecord>(
            predicate: #Predicate { $0.date == target }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
    }
}

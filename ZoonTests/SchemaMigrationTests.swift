import SwiftData
import XCTest

/// Audit §13: the schema is versioned, and a store written by a build from
/// before versioning opens under the migration plan with nothing lost.
///
/// Containers are held on the test case (see
/// `SleepHistoryStoreIntegrationTests` for why a container released while its
/// context is in use traps), and the old store's container is released
/// inside an autorelease pool before the new one opens the same file.
@MainActor
final class SchemaMigrationTests: XCTestCase {

    private var containers: [ModelContainer] = []
    private var directory: URL?

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
    }

    override func tearDownWithError() throws {
        containers.removeAll()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private static let unversionedModels: [any PersistentModel.Type] = [
        SleepNightRecord.self, JournalEntry.self, SleepEpisodeRecord.self,
        BehaviorObservationRecord.self, EvidenceRevisionRecord.self
    ]

    func testTheVersionedSchemaIsTheShippedSchema() {
        let versioned = Set(Schema(versionedSchema: ZoonSchemaV1.self).entities.map(\.name))
        let shipped = Set(Schema(Self.unversionedModels).entities.map(\.name))
        XCTAssertEqual(versioned, shipped)
        XCTAssertEqual(Set(PersistentStore.schema.entities.map(\.name)), shipped)
        XCTAssertEqual(ZoonSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }

    /// Until a V2 exists there is nothing to migrate, and no stage that
    /// could drop rows.
    func testThePlanHasOneVersionAndNoStages() {
        XCTAssertEqual(ZoonMigrationPlan.schemas.map { ObjectIdentifier($0) }, [ObjectIdentifier(ZoonSchemaV1.self)])
        XCTAssertTrue(ZoonMigrationPlan.stages.isEmpty)
    }

    func testAStoreWrittenBeforeVersioningOpensWithEverythingIntact() throws {
        let url = try XCTUnwrap(directory).appendingPathComponent("Zoon.store")
        let wake = Calendar.current.startOfDay(for: .now)
        let revision = EvidenceLedger.Revision(
            claimID: "tag:alcohol", recordedAt: wake, status: .associated,
            headline: "A private observation", effect: -12, effectUnit: "minutes",
            uncertaintyLower: -20, uncertaintyUpper: -4, sampleSize: 14,
            windowStart: nil, windowEnd: nil, algorithmVersion: 3,
            sourceFeature: "sleep", provenance: "fixture"
        )

        // Written the way every shipped build wrote it: one plain schema, no
        // version, no plan.
        try autoreleasepool {
            let unversioned = Schema(Self.unversionedModels)
            let old = try ModelContainer(
                for: unversioned,
                configurations: ModelConfiguration(schema: unversioned, url: url, cloudKitDatabase: .none)
            )
            let context = old.mainContext
            let features = Fixture.night(
                daysAgo: 1,
                sourceName: "Apple Watch",
                sourceBundleIdentifier: "com.apple.health.watch",
                timeZoneIdentifier: "Asia/Kolkata"
            )
            context.insert(SleepNightRecord(features: features, absoluteWristTempC: 34.2, nightKey: "night-key-1"))
            context.insert(JournalEntry(date: wake, tags: [.alcohol], note: "Late dinner", nightKey: "night-key-1"))
            context.insert(SleepEpisodeRecord(
                id: "episode-1", nightKey: "night-key-1", startDate: wake.addingTimeInterval(13 * 3_600),
                endDate: wake.addingTimeInterval(13.5 * 3_600), timezoneIdentifier: "Asia/Kolkata",
                episodeType: .nap, asleepMinutes: 24, timeInBedMinutes: 30, sourceName: "Apple Watch"
            ))
            context.insert(BehaviorObservationRecord(
                nightKey: "night-key-1", behaviorIdentifier: "alcohol", state: .yes, source: .manual
            ))
            context.insert(EvidenceRevisionRecord(revision))
            try context.save()
        }

        // Opened the way the app now opens it.
        let reopened = try ModelContainer(
            for: PersistentStore.schema,
            migrationPlan: ZoonMigrationPlan.self,
            configurations: ModelConfiguration(schema: PersistentStore.schema, url: url, cloudKitDatabase: .none)
        )
        containers.append(reopened)
        let context = reopened.mainContext

        let nights = try context.fetch(FetchDescriptor<SleepNightRecord>())
        XCTAssertEqual(nights.count, 1)
        let night = try XCTUnwrap(nights.first)
        XCTAssertEqual(night.nightKey, "night-key-1")
        XCTAssertEqual(night.timeZoneIdentifier, "Asia/Kolkata")
        XCTAssertEqual(night.sourceName, "Apple Watch")
        XCTAssertEqual(night.sourceBundleIdentifier, "com.apple.health.watch")
        XCTAssertEqual(night.wristTempAbsoluteC, 34.2)

        let journal = try context.fetch(FetchDescriptor<JournalEntry>())
        XCTAssertEqual(journal.map(\.note), ["Late dinner"])
        XCTAssertEqual(journal.first?.nightKey, "night-key-1")
        XCTAssertEqual(journal.first?.tags, [.alcohol])

        let episodes = try context.fetch(FetchDescriptor<SleepEpisodeRecord>())
        XCTAssertEqual(episodes.map(\.id), ["episode-1"])
        XCTAssertEqual(episodes.first?.timezoneIdentifier, "Asia/Kolkata")
        XCTAssertEqual(episodes.first?.asleepMinutes, 24)

        let behaviors = try context.fetch(FetchDescriptor<BehaviorObservationRecord>())
        XCTAssertEqual(behaviors.count, 1)
        XCTAssertEqual(behaviors.first?.state, .yes)
        XCTAssertEqual(behaviors.first?.nightKey, "night-key-1")

        let evidence = try context.fetch(FetchDescriptor<EvidenceRevisionRecord>()).map(\.revision)
        XCTAssertEqual(evidence, [revision])
        XCTAssertEqual(evidence.first?.algorithmVersion, 3)
    }
}

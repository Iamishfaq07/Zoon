import XCTest
import SwiftData

final class PersistentStoreSchemaTests: XCTestCase {
    func testSchemaIncludesEveryPersistedModel() {
        let names = Set(PersistentStore.schema.entities.map(\.name))
        XCTAssertEqual(
            names,
            [
                "SleepNightRecord",
                "JournalEntry",
                "SleepEpisodeRecord",
                "BehaviorObservationRecord",
                "EvidenceRevisionRecord",
            ]
        )
    }
}

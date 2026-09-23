import Foundation

/// The sources a sleep-source picker offers.
enum SleepSourceList {

    /// Stored winners and HealthKit's writers, one row per name.
    ///
    /// Stored nights only know the source that *won* them, so a writer that
    /// always lost the overlap was never listed and could never be chosen --
    /// the case a preferred-source setting exists for. A writer's bundle
    /// identifier also fills a stored row that predates that column.
    static func merged(
        stored: [(name: String, bundleIdentifier: String?)],
        writers: [(name: String, bundleIdentifier: String)]
    ) -> [(name: String, bundleIdentifier: String?)] {
        var byName: [String: String?] = [:]
        for source in stored { byName[source.name] = source.bundleIdentifier }
        for writer in writers where (byName[writer.name] ?? nil) == nil {
            byName[writer.name] = writer.bundleIdentifier
        }
        return byName.map { (name: $0.key, bundleIdentifier: $0.value) }.sorted { $0.name < $1.name }
    }
}

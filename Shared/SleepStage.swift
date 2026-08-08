import Foundation

/// Sleep stages, independent of HealthKit.
///
/// This used to live next to the HealthKit sample parsing, which meant the
/// widget couldn't name a stage without importing HealthKit. The raw-value
/// mapping now lives in an extension in the app target (`SleepSessionBuilder`);
/// the vocabulary itself lives here, where both targets and the hypnogram
/// renderer can reach it.
enum SleepStage: String, Codable, Hashable, CaseIterable, Sendable {
    case inBed
    case awake
    case core
    case deep
    case rem
    /// Sleep with no stage detail — what non-Watch sources write.
    case unspecified

    /// Every value that counts as sleep. `inBed` and `awake` are not sleep.
    static let asleepStages: [SleepStage] = [.core, .deep, .rem, .unspecified]

    var displayName: String {
        switch self {
        case .inBed: "In Bed"
        case .awake: "Awake"
        case .core: "Core"
        case .deep: "Deep"
        case .rem: "REM"
        case .unspecified: "Asleep"
        }
    }

    /// Vertical position in a hypnogram, 0 = deepest at the bottom.
    ///
    /// The conventional ordering puts Awake at the top and Deep at the bottom,
    /// so the trace visibly "descends" into deep sleep early in the night and
    /// climbs toward REM before waking — the shape people recognise.
    var depthLevel: Int {
        switch self {
        case .awake, .inBed: 3
        case .rem: 2
        case .core, .unspecified: 1
        case .deep: 0
        }
    }

    static let hypnogramOrder: [SleepStage] = [.awake, .rem, .core, .deep]
}

/// One contiguous run of a single stage.
///
/// The night's shape, not just its totals. Persisted per night so the hypnogram
/// can be redrawn without re-querying HealthKit — which matters because the
/// samples behind a night older than the sync window may no longer be reachable.
struct StageSegment: Codable, Hashable, Sendable, Identifiable {
    let stage: SleepStage
    let start: Date
    let end: Date

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
    var minutes: Double { duration / 60 }
}

extension Array where Element == StageSegment {

    /// Chronological span covered by these segments.
    var span: DateInterval? {
        guard let first = self.map(\.start).min(), let last = self.map(\.end).max() else { return nil }
        return DateInterval(start: first, end: last)
    }

    /// Total minutes for one stage.
    func minutes(of stage: SleepStage) -> Double {
        filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
    }

    /// JSON round-trip used to store the timeline on a SwiftData row.
    ///
    /// A blob rather than a relationship: the timeline is only ever read as a
    /// whole, never queried into, and a to-many relationship of 30–80 rows per
    /// night would multiply the store size for no benefit.
    var encoded: Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(self)
    }

    static func decode(_ data: Data?) -> [StageSegment] {
        guard let data else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([StageSegment].self, from: data)) ?? []
    }
}

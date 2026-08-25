import Foundation

/// History of completed Guided Experiments, each snapshotting a baseline
/// (before) vs. trial (during) comparison at the moment the experiment ended.
///
/// Backed by `UserDefaults` rather than SwiftData, same reasoning as
/// `NapStore`: a short, append-only list of small records, read in bulk and
/// never queried into.
///
/// Snapshotted rather than recomputed on every read: the whole point is
/// "what did this experiment actually show", and letting that answer drift
/// as new, unrelated nights accumulate afterward would misrepresent what the
/// user was actually testing at the time.
@MainActor
@Observable
final class SleepExperimentStore {

    struct Outcome: Codable, Identifiable, Hashable, Sendable {
        let id: UUID
        let tag: String
        let hypothesis: String?
        let startDate: Date
        let endDate: Date
        /// `JournalCorrelator.Metric.shortLabel` for whichever metric moved
        /// most between the two periods.
        let metricLabel: String
        let baselineMedian: Double
        let trialMedian: Double
        let baselineNightCount: Int
        let trialNightCount: Int
        let higherIsBetter: Bool
        /// How many of the trial nights had a known yes/no for the tracked
        /// behaviour, out of `trialNightCount`. `nil` for outcomes recorded
        /// before this field existed -- there's no way to reconstruct it
        /// after the fact, so those just don't show this figure.
        var trialKnownNightCount: Int?
        /// Which side of the tag this experiment was testing for -- cutting
        /// back on it, or doing more of it. `nil` for outcomes recorded
        /// before this existed, in which case `adherenceRate` below can't be
        /// computed and stays `nil` too.
        var direction: GuidedExperiment.Direction?
        /// How many trial nights actually landed on the compliant side of
        /// `direction`, out of `trialNightCount`. This -- not
        /// `trialKnownNightCount` -- is the real adherence figure: a night
        /// that got tagged but went the wrong way is exactly as much a
        /// non-compliant night as one that never got tagged at all.
        var trialCompliantNightCount: Int?

        var delta: Double { trialMedian - baselineMedian }
        var isImprovement: Bool { higherIsBetter ? delta > 0 : delta < 0 }
        /// Fraction (0...1) of trial nights that were actually compliant
        /// with what this experiment was testing -- out of *all* trial
        /// nights, not just the ones that got logged either way. A trial
        /// with 14 nights, 5 compliant and 9 not, all 14 known, is 36%
        /// adherence: an unlogged night and a logged-but-noncompliant night
        /// are both failures to demonstrate compliance.
        var adherenceRate: Double? {
            guard let trialCompliantNightCount, trialNightCount > 0 else { return nil }
            return Double(trialCompliantNightCount) / Double(trialNightCount)
        }
    }

    private enum Key {
        static let outcomes = "zoon.experiments.outcomes"
    }

    private let defaults: UserDefaults

    private(set) var outcomes: [Outcome] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func record(_ outcome: Outcome) {
        outcomes.insert(outcome, at: 0)
        persist()
    }

    func deleteAll() {
        outcomes = []
        persist()
    }

    /// Restores completed experiments from a backup.
    ///
    /// Merges by `id` rather than replacing, same reasoning as
    /// `NapStore.importNaps`/`SnoreStore.importSummaries`: a device that's
    /// kept running its own experiments since the backup was taken
    /// shouldn't lose them.
    /// - Returns: how many were actually added.
    @discardableResult
    func importOutcomes(_ imported: [Outcome]) -> Int {
        let existingIDs = Set(outcomes.map(\.id))
        let fresh = imported.filter { !existingIDs.contains($0.id) }
        guard !fresh.isEmpty else { return 0 }
        outcomes.append(contentsOf: fresh)
        outcomes.sort { $0.startDate > $1.startDate }
        persist()
        return fresh.count
    }

    private func load() {
        guard let data = defaults.data(forKey: Key.outcomes),
              let decoded = try? JSONDecoder().decode([Outcome].self, from: data) else { return }
        outcomes = decoded
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(outcomes), forKey: Key.outcomes)
    }
}

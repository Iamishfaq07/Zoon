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
        /// after the fact, so those just don't show an adherence figure.
        var trialKnownNightCount: Int?

        var delta: Double { trialMedian - baselineMedian }
        var isImprovement: Bool { higherIsBetter ? delta > 0 : delta < 0 }
        /// Fraction (0...1) of trial nights that had a known yes/no for the
        /// tracked behaviour -- how consistently it actually got logged
        /// once the experiment started, not just how many nights had any
        /// journal entry at all.
        var adherenceRate: Double? {
            guard let trialKnownNightCount, trialNightCount > 0 else { return nil }
            return Double(trialKnownNightCount) / Double(trialNightCount)
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

    private func load() {
        guard let data = defaults.data(forKey: Key.outcomes),
              let decoded = try? JSONDecoder().decode([Outcome].self, from: data) else { return }
        outcomes = decoded
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(outcomes), forKey: Key.outcomes)
    }
}

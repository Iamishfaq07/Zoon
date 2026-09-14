import Foundation

/// Collapses the same workout recorded by more than one source.
///
/// A run recorded by an Apple Watch and mirrored by a third-party app
/// arrives from HealthKit as two `HKWorkout`s: same activity, near-identical
/// window, different UUIDs. Nothing downstream was collapsing them, so the
/// day's workout list showed the run twice — one session, counted as two, on
/// a screen whose whole job is to be trustworthy about the day.
///
/// **Why not just trust HealthKit.** HealthKit stores what each app writes.
/// It does not decide that two writers meant the same session, and there is
/// no public API that does. Arbitration is the consumer's job, which is why
/// `SleepSourceArbitration` already exists for sleep.
///
/// **The rule.** Two workouts are the same session when they share an
/// activity type and their intervals overlap by most of the shorter one.
/// Overlap, not equality: two apps rarely agree on the second, and a
/// start-time tolerance alone would merge a genuine back-to-back pair while
/// missing a mirrored session that began a minute late.
///
/// The winner is the higher-priority source — the same `SourcePriority`
/// ladder sleep arbitration uses — and, on a tie, the longer recording, which
/// is the one less likely to have been cut short by a dropped connection.
/// Deliberately *not* the union: a session neither device reported is exactly
/// the fabrication the rest of this work removes.
enum WorkoutDeduplicator {

    /// A workout reduced to what arbitration needs, so this is testable
    /// without an `HKWorkout` (whose `sourceRevision` cannot be constructed).
    struct Candidate: Hashable, Sendable, Identifiable {
        let id: UUID
        let activityLabel: String
        let start: Date
        let end: Date
        let priority: SourcePriority

        var duration: TimeInterval { end.timeIntervalSince(start) }
        var interval: DateInterval { DateInterval(start: start, end: max(end, start)) }

        init(
            id: UUID = UUID(),
            activityLabel: String,
            start: Date,
            end: Date,
            priority: SourcePriority
        ) {
            self.id = id
            self.activityLabel = activityLabel
            self.start = start
            self.end = end
            self.priority = priority
        }
    }

    /// How much of the shorter session must be covered by the longer one
    /// before they are treated as one recording.
    ///
    /// 0.8 rather than something near 1.0: mirrored sessions routinely differ
    /// by a minute or two at each end, and a 40-minute run recorded as 38 by
    /// one app is 0.95 — but a 10-minute warm-up logged separately inside an
    /// hour-long session is only 0.17 of the *longer* one and 1.0 of the
    /// shorter, which is why the test is on the shorter session and the
    /// threshold is not 1.0.
    static let sameSessionOverlapFraction: Double = 0.8

    /// - Returns: one entry per real session, in start order.
    static func deduplicate(_ candidates: [Candidate]) -> [Candidate] {
        let sorted = candidates.sorted { $0.start < $1.start }
        var kept: [Candidate] = []

        for candidate in sorted {
            if let index = kept.firstIndex(where: { isSameSession($0, candidate) }) {
                kept[index] = preferred(kept[index], candidate)
            } else {
                kept.append(candidate)
            }
        }

        return kept.sorted { $0.start < $1.start }
    }

    static func isSameSession(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        guard lhs.activityLabel == rhs.activityLabel else { return false }
        let shorter = min(lhs.duration, rhs.duration)
        // Two zero-length records of the same activity at the same instant
        // are still the same record; without this they never overlap by any
        // fraction and both survive.
        guard shorter > 0 else { return lhs.start == rhs.start }
        guard let overlap = lhs.interval.intersection(with: rhs.interval) else { return false }
        return overlap.duration / shorter >= sameSessionOverlapFraction
    }

    /// Higher priority wins; on a tie the longer recording does.
    static func preferred(_ lhs: Candidate, _ rhs: Candidate) -> Candidate {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority ? lhs : rhs
        }
        return lhs.duration >= rhs.duration ? lhs : rhs
    }
}

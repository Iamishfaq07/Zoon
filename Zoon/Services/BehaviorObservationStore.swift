import Foundation
import SwiftData
import os

/// SwiftData access for durable per-behaviour answers.
///
/// Sits alongside `JournalStore` rather than inside it because the two answer
/// different questions and have different lifetimes. A `JournalEntry` is a
/// day's scratchpad -- free-text note, morning check-in, and (historically) a
/// set of positive tags. A `BehaviorObservationRecord` is a claim about one
/// behaviour on one night, and it is the only thing `JournalCorrelator` is
/// allowed to build a control arm out of.
@MainActor
final class BehaviorObservationStore {

    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "BehaviorObservationStore")

    /// Set once the one-time forward-fill of legacy positive tags has run.
    private static let migrationKey = "zoon.behaviorObservations.didMigrateLegacyTags"

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Reading

    func allRecords() -> [BehaviorObservationRecord] {
        let descriptor = FetchDescriptor<BehaviorObservationRecord>(
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func answers(forNightKey nightKey: String) -> BehaviorAnswers {
        let descriptor = FetchDescriptor<BehaviorObservationRecord>(
            predicate: #Predicate { $0.nightKey == nightKey }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return Self.answers(from: records)
    }

    /// Every night's answers in one fetch.
    ///
    /// Batched deliberately: `SleepDataCoordinator.journalObservations()`
    /// builds an `Observation` per night across the whole history window, and
    /// a per-night fetch there would issue one query per night on a path that
    /// several SwiftUI view bodies already call more than once per render.
    func allAnswersByNightKey() -> [String: BehaviorAnswers] {
        Dictionary(grouping: allRecords(), by: \.nightKey)
            .mapValues { Self.answers(from: $0) }
    }

    private static func answers(from records: [BehaviorObservationRecord]) -> BehaviorAnswers {
        var states: [String: BehaviorObservationState] = [:]
        for record in records where record.state != .unknown {
            states[record.behaviorIdentifier] = record.state
        }
        return BehaviorAnswers(states)
    }

    func record(nightKey: String, behaviorIdentifier: String) -> BehaviorObservationRecord? {
        let identity = BehaviorObservationRecord.identity(
            nightKey: nightKey, behaviorIdentifier: behaviorIdentifier
        )
        let descriptor = FetchDescriptor<BehaviorObservationRecord>(
            predicate: #Predicate { $0.id == identity }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Writing

    /// Records an answer, or clears it when `state` is `.unknown`.
    ///
    /// Clearing deletes the row rather than storing `.unknown`, so an absent
    /// row is the single representation of "never answered".
    func set(
        _ state: BehaviorObservationState,
        for tag: BehaviorTag,
        nightKey: String,
        source: BehaviorObservationSource = .manual
    ) {
        guard state != .unknown else {
            clear(tag, nightKey: nightKey)
            return
        }
        if let existing = record(nightKey: nightKey, behaviorIdentifier: tag.rawValue) {
            existing.state = state
            existing.source = source
        } else {
            context.insert(BehaviorObservationRecord(
                nightKey: nightKey,
                behaviorIdentifier: tag.rawValue,
                state: state,
                source: source
            ))
        }
        save()
    }

    func clear(_ tag: BehaviorTag, nightKey: String) {
        guard let existing = record(nightKey: nightKey, behaviorIdentifier: tag.rawValue) else { return }
        context.delete(existing)
        save()
    }

    /// Advances one behaviour through unanswered, yes, no, unanswered.
    ///
    /// Lives here rather than in the view so the phone, a future watch action
    /// and any App Intent cannot each implement a slightly different cycle.
    /// - Returns: the state now recorded.
    @discardableResult
    func cycle(_ tag: BehaviorTag, nightKey: String) -> BehaviorObservationState {
        let next: BehaviorObservationState
        switch answers(forNightKey: nightKey).state(for: tag) {
        case .unknown: next = .yes
        case .yes: next = .no
        case .no: next = .unknown
        }
        set(next, for: tag, nightKey: nightKey)
        return next
    }

    /// Answers every still-unanswered candidate `.no` for one night.
    ///
    /// The "nothing else applied" action. This is the only bulk writer of
    /// negatives in the app, and it is user-initiated on purpose: the whole
    /// defect this model replaced was negative evidence appearing without
    /// anyone having said anything.
    /// - Returns: how many answers were recorded.
    @discardableResult
    func answerRemainingNo(
        nightKey: String,
        candidates: [BehaviorTag] = BehaviorTag.allCases
    ) -> Int {
        let existing = answers(forNightKey: nightKey)
        var recorded = 0
        for tag in candidates where existing.state(for: tag) == .unknown {
            context.insert(BehaviorObservationRecord(
                nightKey: nightKey,
                behaviorIdentifier: tag.rawValue,
                state: .no,
                source: .manual
            ))
            recorded += 1
        }
        if recorded > 0 { save() }
        return recorded
    }

    // MARK: - Migration

    /// Forward-fills `.yes` answers from the legacy `JournalEntry` tag sets.
    ///
    /// Only positives, and only for entries that carry a `nightKey`. Two
    /// deliberate limits:
    ///
    /// 1. No negatives, ever. A tag absent from a legacy entry is `.unknown`,
    ///    not `.no`. The old model could not distinguish "reviewed and did
    ///    not apply" from "never asked", and writing `.no` would make that
    ///    ambiguity permanent and invisible.
    /// 2. Keyed entries only. An entry predating `JournalEntry.nightKey` has
    ///    no night identity to attach an observation to. Those are not lost:
    ///    `exposureState(for:)` keeps treating a legacy positive tag as a
    ///    `.yes`, so historical positives still reach every engine by that
    ///    route whether or not they were forward-filled here.
    ///
    /// Idempotent. An observation that already exists is skipped rather than
    /// overwritten, so an answer the user has since changed is never
    /// clobbered by a re-run.
    /// - Returns: how many observations were created.
    @discardableResult
    func migrateLegacyTags(
        from entries: [JournalEntry],
        force: Bool = false,
        defaults: UserDefaults = .standard
    ) -> Int {
        guard force || !defaults.bool(forKey: Self.migrationKey) else { return 0 }

        var existingIdentities = Set(allRecords().map(\.id))
        var created = 0
        for entry in entries {
            guard let nightKey = entry.nightKey else { continue }
            for identifier in entry.tagIdentifiers {
                let identity = BehaviorObservationRecord.identity(
                    nightKey: nightKey, behaviorIdentifier: identifier
                )
                guard !existingIdentities.contains(identity) else { continue }
                context.insert(BehaviorObservationRecord(
                    nightKey: nightKey,
                    behaviorIdentifier: identifier,
                    state: .yes,
                    source: .manual,
                    observedAt: entry.updatedAt
                ))
                existingIdentities.insert(identity)
                created += 1
            }
        }
        save()
        defaults.set(true, forKey: Self.migrationKey)
        return created
    }

    // MARK: - Deletion

    @discardableResult
    func deleteAll() -> Bool {
        do {
            try context.delete(model: BehaviorObservationRecord.self)
            try context.save()
            return true
        } catch {
            logger.error("Observation delete-all failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Observation save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

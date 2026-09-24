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
        return context.readAll(descriptor, operation: "behaviors.all") ?? []
    }

    func answers(forNightKey nightKey: String) -> BehaviorAnswers {
        let descriptor = FetchDescriptor<BehaviorObservationRecord>(
            predicate: #Predicate { $0.nightKey == nightKey }
        )
        let records = context.readAll(descriptor, operation: "behaviors.forNight") ?? []
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
        lookupRecord(nightKey: nightKey, behaviorIdentifier: behaviorIdentifier).value
    }

    private func lookupRecord(nightKey: String, behaviorIdentifier: String) -> StoreLookup<BehaviorObservationRecord> {
        let identity = BehaviorObservationRecord.identity(
            nightKey: nightKey, behaviorIdentifier: behaviorIdentifier
        )
        let descriptor = FetchDescriptor<BehaviorObservationRecord>(
            predicate: #Predicate { $0.id == identity }
        )
        return context.lookupFirst(descriptor, operation: "behaviors.record")
    }

    // MARK: - Writing

    /// Records an answer, or clears it when `state` is `.unknown`.
    ///
    /// Clearing deletes the row rather than storing `.unknown`, so an absent
    /// row is the single representation of "never answered".
    /// - Parameter detail: the structured part, when the person confirmed
    ///   one. Never inferred: the default is `nil`, every existing caller
    ///   keeps writing yes/no rows, and the only thing that supplies a value
    ///   is a confirmation the person made. See `BehaviorDetail`.
    ///
    ///   Passing `nil` on an update **clears** any detail already stored, for
    ///   the same reason clearing a state deletes the row: if editing an
    ///   answer left last week's quantity attached to it, the row would be a
    ///   mixture of two answers and nothing downstream could tell.
    func set(
        _ state: BehaviorObservationState,
        for behavior: BehaviorID,
        nightKey: String,
        source: BehaviorObservationSource = .manual,
        detail: BehaviorDetail? = nil
    ) {
        guard state != .unknown else {
            clear(behavior, nightKey: nightKey)
            return
        }

        // Only a person can say a behaviour did not happen.
        //
        // `BehaviorObservationSource` documents this for every case -- an
        // absent HealthKit sample means "nothing logged *or* the type was
        // never authorized", which Apple deliberately makes
        // indistinguishable, and a same-timezone trip is real travel the
        // derived rule cannot see. Absence of evidence, from either, is not
        // evidence of absence.
        //
        // Until now that rule lived only in comments. Nothing passes a
        // non-manual source yet, so this fixes no live bug; it closes the
        // door before the first HealthKit ingestion caller arrives, because
        // one wrong argument there silently rebuilds the fabricated control
        // arm this whole model exists to remove -- and it would rebuild it
        // invisibly, as a plausible-looking Cause Finder result.
        //
        // Refused rather than trapped: a crash in a background ingest is a
        // worse outcome than a dropped write, and the prior state (usually
        // `.unknown`, which is the truth) survives either way.
        guard state != .no || source == .manual else {
            logger.error("""
                Refused a .no for \(behavior.identifier, privacy: .public) from                 \(source.rawValue, privacy: .public): only a manual answer                 can assert that a behaviour did not happen.
                """)
            return
        }
        // A behaviour that did not happen has no quantity, no time and no
        // intensity. Storing them against a `.no` would be detail about an
        // event nobody had.
        let detail = state == .no ? nil : detail

        let lookup = lookupRecord(nightKey: nightKey, behaviorIdentifier: behavior.identifier)
        // Could not look for the existing answer: write nothing rather than
        // a second row for the same night and behaviour.
        if case .unreadable = lookup { return }
        if let existing = lookup.value {
            existing.state = state
            existing.source = source
            existing.detail = detail
        } else {
            context.insert(BehaviorObservationRecord(
                nightKey: nightKey,
                behaviorIdentifier: behavior.identifier,
                state: state,
                source: source,
                detail: detail
            ))
        }
        save()
    }

    /// Built-in convenience. The identifier written is `tag.rawValue`, which
    /// is what every row ever written already uses, so nothing migrates.
    func set(
        _ state: BehaviorObservationState,
        for tag: BehaviorTag,
        nightKey: String,
        source: BehaviorObservationSource = .manual,
        detail: BehaviorDetail? = nil
    ) {
        set(state, for: tag.behaviorID, nightKey: nightKey, source: source, detail: detail)
    }

    /// Every stored detail for a behaviour, with the night it belongs to.
    ///
    /// The read side §18's curves take: a dose or a clock time per night,
    /// drawn only from rows somebody confirmed. Nights with no detail are
    /// absent rather than zero -- a night recorded as "coffee" with no number
    /// is a night with an unknown number of coffees, and putting it in the
    /// control band would build a curve out of nothing.
    func details(for behavior: BehaviorID) -> [(nightKey: String, detail: BehaviorDetail)] {
        allRecords()
            .filter { $0.behaviorIdentifier == behavior.identifier && $0.state == .yes }
            .compactMap { record in
                record.detail.map { (nightKey: record.nightKey, detail: $0) }
            }
    }

    func clear(_ behavior: BehaviorID, nightKey: String) {
        guard let existing = record(nightKey: nightKey, behaviorIdentifier: behavior.identifier) else { return }
        context.delete(existing)
        save()
    }

    func clear(_ tag: BehaviorTag, nightKey: String) {
        clear(tag.behaviorID, nightKey: nightKey)
    }

    /// Advances one behaviour through unanswered, yes, no, unanswered.
    ///
    /// Lives here rather than in the view so the phone, a future watch action
    /// and any App Intent cannot each implement a slightly different cycle.
    /// - Returns: the state now recorded.
    @discardableResult
    func cycle(_ behavior: BehaviorID, nightKey: String) -> BehaviorObservationState {
        let next: BehaviorObservationState
        switch answers(forNightKey: nightKey).state(forIdentifier: behavior.identifier) {
        case .unknown: next = .yes
        case .yes: next = .no
        case .no: next = .unknown
        }
        set(next, for: behavior, nightKey: nightKey)
        return next
    }

    @discardableResult
    func cycle(_ tag: BehaviorTag, nightKey: String) -> BehaviorObservationState {
        cycle(tag.behaviorID, nightKey: nightKey)
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

    // MARK: - Backup

    func observationsForExport() -> [DataExporter.Archive.BehaviorObservationRecordExport] {
        allRecords().map {
            DataExporter.Archive.BehaviorObservationRecordExport(
                nightKey: $0.nightKey,
                behaviorIdentifier: $0.behaviorIdentifier,
                state: $0.stateRaw,
                source: $0.sourceRaw,
                observedAt: $0.observedAt,
                // The detail travels with the answer. Dropping it restored
                // "had caffeine" without the 14:30 and the 2 cups that made
                // the answer worth giving.
                quantity: $0.quantity,
                unit: $0.unit,
                eventTime: $0.eventTime,
                intensity: $0.intensity
            )
        }
    }

    /// Restores answers from a backup.
    ///
    /// Existing answers win on conflict, the same rule
    /// `JournalStore.importEntries` follows: an answer given on this
    /// device is more trustworthy than one from an older archive. An
    /// unrecognised state raw value is skipped rather than stored, so a
    /// corrupt or future archive cannot inject a row that reads as
    /// `.unknown` yet still occupies the identity.
    /// - Returns: how many answers were created.
    @discardableResult
    func importObservations(
        _ imported: [DataExporter.Archive.BehaviorObservationRecordExport]
    ) -> Int {
        var existingIdentities = Set(allRecords().map(\.id))
        var created = 0
        for record in imported {
            guard let state = BehaviorObservationState(rawValue: record.state),
                  state != .unknown else { continue }
            let identity = BehaviorObservationRecord.identity(
                nightKey: record.nightKey, behaviorIdentifier: record.behaviorIdentifier
            )
            guard !existingIdentities.contains(identity) else { continue }
            context.insert(BehaviorObservationRecord(
                nightKey: record.nightKey,
                behaviorIdentifier: record.behaviorIdentifier,
                state: state,
                source: BehaviorObservationSource(rawValue: record.source) ?? .manual,
                observedAt: record.observedAt,
                detail: BehaviorDetail(
                    quantity: record.quantity,
                    unit: record.unit,
                    eventTime: record.eventTime,
                    intensity: record.intensity
                )
            ))
            existingIdentities.insert(identity)
            created += 1
        }
        if created > 0 { save() }
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

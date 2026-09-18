import Foundation
import SwiftData

/// One durable answer to "did this behaviour happen on this night".
///
/// A row per (night, behaviour) rather than a set of positive tags per night,
/// because the set-of-tags shape cannot represent the answer that matters
/// most: an explicit "no". See `BehaviorObservationState` for why inferring
/// that from journal-row existence was invalid.
///
/// Keyed on `nightKey` rather than on a calendar date. A night's key is
/// computed from the timezone that night actually happened in, whereas a
/// `Date` day-boundary is computed from `Calendar.current` at whatever moment
/// the row was written -- the two disagree exactly on travel days, which is
/// when a silently dropped join does the most damage. `JournalEntry.nightKey`
/// exists for the same reason and documents it at length.
@Model
final class BehaviorObservationRecord {

    /// `"<nightKey>|<behaviorIdentifier>"`.
    ///
    /// SwiftData's `.unique` applies to a single attribute, so the composite
    /// identity is folded into one column rather than enforced by convention
    /// at every call site. `|` is not a legal character in either component
    /// (`nightKey` is a date-derived string, identifiers are enum raw values),
    /// so the join is unambiguous.
    @Attribute(.unique) var id: String

    var nightKey: String

    /// `BehaviorTag.rawValue`. A `String` for the same reason
    /// `JournalEntry.tagIdentifiers` is: a value written by a future build
    /// decays to "ignored" rather than failing to decode the row.
    var behaviorIdentifier: String

    /// `BehaviorObservationState.rawValue`. `.unknown` is never persisted --
    /// clearing an answer deletes the row, so an absent row is the single
    /// representation of "never answered" and there is no second one to keep
    /// in sync.
    var stateRaw: String

    /// `BehaviorObservationSource.rawValue`.
    var sourceRaw: String

    var observedAt: Date

    // MARK: - Structured detail (§9)
    //
    // Four optional columns rather than one encoded blob, so a future query
    // can filter on a time or a dose without decoding every row -- and so the
    // migration is the free one. SwiftData adds a new *optional* property to
    // an existing store without a mapping model or a version plan; every row
    // written before this build simply reads back with `nil` in all four,
    // which is the truth about those rows. A non-optional column, or a
    // renamed one, would have needed a `VersionedSchema` and a migration
    // stage, and would have had to invent a value for history that has none.
    //
    // Absent is not zero here, and the accessors below never substitute one.

    /// How many, when the person said. See `BehaviorDetail.quantity`.
    var quantity: Double?

    /// What `quantity` counts, in the person's own word.
    var unit: String?

    /// When it happened -- the last occurrence, where there were several.
    var eventTime: Date?

    /// How hard, 0-1, where the behaviour has a natural intensity.
    var intensity: Double?

    /// The structured detail as one value, or `nil` when the row carries
    /// none -- which is every row written before this build, and every row
    /// since where the person confirmed only a yes or a no.
    var detail: BehaviorDetail? {
        get {
            let detail = BehaviorDetail(
                quantity: quantity, unit: unit, eventTime: eventTime, intensity: intensity
            )
            return detail.isEmpty ? nil : detail
        }
        set {
            quantity = newValue?.quantity
            unit = newValue?.unit
            eventTime = newValue?.eventTime
            intensity = newValue?.intensity
            observedAt = .now
        }
    }

    init(
        nightKey: String,
        behaviorIdentifier: String,
        state: BehaviorObservationState,
        source: BehaviorObservationSource,
        observedAt: Date = .now,
        /// Never inferred. A caller passes this only when the person
        /// confirmed it -- see `BehaviorDetail`.
        detail: BehaviorDetail? = nil
    ) {
        self.id = Self.identity(nightKey: nightKey, behaviorIdentifier: behaviorIdentifier)
        self.nightKey = nightKey
        self.behaviorIdentifier = behaviorIdentifier
        self.stateRaw = state.rawValue
        self.sourceRaw = source.rawValue
        self.observedAt = observedAt
        self.quantity = detail?.quantity
        self.unit = detail?.unit
        self.eventTime = detail?.eventTime
        self.intensity = detail?.intensity
    }

    static func identity(nightKey: String, behaviorIdentifier: String) -> String {
        "\(nightKey)|\(behaviorIdentifier)"
    }

    /// Identity for a day answered before any night exists for it --
    /// tonight, before the user has slept, or a gap in history.
    ///
    /// Cannot collide with a real `SleepNightFeatures.nightKey`, which is
    /// always `yyyy-MM-dd@<timezone identifier>`; this deliberately omits
    /// the `@` suffix and adds a prefix. Answers stored under a
    /// provisional key are found by the fallback lookup in
    /// `SleepDataCoordinator.journalObservations()` and are superseded --
    /// not deleted -- once a real key exists for that date, since the
    /// real key is consulted first.
    static func provisionalNightKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "pending:%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Falls back to `.unknown` for a raw value this build doesn't recognise,
    /// which then reads as "no answer" everywhere downstream -- the safe
    /// direction, and the same decay strategy `JournalEntry.tags` uses.
    var state: BehaviorObservationState {
        get { BehaviorObservationState(rawValue: stateRaw) ?? .unknown }
        set {
            stateRaw = newValue.rawValue
            observedAt = .now
        }
    }

    var source: BehaviorObservationSource {
        get { BehaviorObservationSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var tag: BehaviorTag? { BehaviorTag(rawValue: behaviorIdentifier) }
}

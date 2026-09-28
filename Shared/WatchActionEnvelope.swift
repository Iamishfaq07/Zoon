import Foundation

/// Immutable event time and identity survive hours of offline Watch delivery.
struct WatchActionEnvelope: Codable, Sendable {
    let id: UUID
    let occurredAt: Date
    let timeZoneIdentifier: String
    let targetDate: Date
    let action: WatchQuickAction

    init(action: WatchQuickAction, occurredAt: Date = .now,
         timeZone: TimeZone = .current, snapshotDate: Date? = nil, id: UUID = UUID()) {
        self.id = id
        self.action = action
        self.occurredAt = occurredAt
        self.timeZoneIdentifier = timeZone.identifier
        if case .morningFeeling = action {
            self.targetDate = snapshotDate ?? occurredAt
        } else {
            self.targetDate = occurredAt
        }
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return calendar
    }

    /// The night a behaviour logged at `targetDate` belongs to: the one that
    /// follows the day it happened on, keyed by the morning it ends on. A
    /// tag pressed at 21:00 on the 10th is about the night ending on the
    /// 11th. In the watch's own timezone at the time, not the phone's now.
    /// Only meaningful for `.behaviorTag` and `.behaviorAnswer`; a morning
    /// feeling or a midnight awakening is about the night already slept.
    ///
    /// **After midnight is the night in progress.** A tag pressed at 01:00 on
    /// Tuesday is about the night that ends on Tuesday morning, not the one
    /// ending Wednesday: the person has not slept yet. Adding a day to every
    /// event put it on Wednesday. Events before `morningBoundaryMinute`
    /// therefore stay on their own day. The boundary is deliberately early
    /// -- 04:00 -- because a log at 05:30 is more often somebody already up
    /// than somebody not yet asleep; a phone that knows the person's own
    /// wake can pass a better one.
    var behaviorNightDate: Date { behaviorNightDate(morningBoundaryMinute: Self.defaultMorningBoundaryMinute) }

    static let defaultMorningBoundaryMinute = BehaviorNight.defaultMorningBoundaryMinute

    /// Shares its rule with every phone surface through `BehaviorNight`.
    func behaviorNightDate(morningBoundaryMinute: Int) -> Date {
        BehaviorNight.nightDate(forLogAt: targetDate, calendar: calendar, morningBoundaryMinute: morningBoundaryMinute)
    }
}

/// Retained across data erasure so an offline Watch cannot resurrect erased logs.
struct WatchActionReceiptStore {
    let defaults: UserDefaults
    private let key = "zoon.watch.actionReceipts.v1"
    private let erasedKey = "zoon.watch.actionsErasedAt"

    func erase(at date: Date = .now) {
        defaults.set(date, forKey: erasedKey)
        defaults.removeObject(forKey: key)
    }

    func accepts(_ event: WatchActionEnvelope, now: Date = .now) -> Bool {
        guard event.occurredAt <= now.addingTimeInterval(300),
              event.occurredAt > now.addingTimeInterval(-90 * 86_400),
              // The night a log is filed against is the tap itself or the
              // night the watch last showed, so it sits just before the tap.
              // Anything further out is a malformed packet, and filing it
              // would write to a night the person never touched.
              event.targetDate <= event.occurredAt.addingTimeInterval(86_400),
              event.targetDate >= event.occurredAt.addingTimeInterval(-14 * 86_400),
              TimeZone(identifier: event.timeZoneIdentifier) != nil else { return false }
        if let erased = defaults.object(forKey: erasedKey) as? Date,
           event.occurredAt <= erased || event.targetDate <= erased { return false }
        return !(defaults.stringArray(forKey: key) ?? []).contains(event.id.uuidString)
    }

    /// Whether this exact envelope has already been applied. Distinguishes
    /// the two reasons `accepts` says no: a redelivery of something already
    /// written (which the watch should be told succeeded) from a packet out
    /// of window or erased (which it should be told failed).
    func hasRecorded(_ event: WatchActionEnvelope) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(event.id.uuidString)
    }

    func record(_ event: WatchActionEnvelope) {
        var receipts = defaults.stringArray(forKey: key) ?? []
        receipts.append(event.id.uuidString)
        // Bounded. An envelope older than 90 days is refused on its date
        // before its receipt is consulted, so only recent IDs ever matter;
        // unbounded, this list grew by one entry per watch tap forever.
        if receipts.count > Self.receiptLimit { receipts.removeFirst(receipts.count - Self.receiptLimit) }
        defaults.set(receipts, forKey: key)
    }

    static let receiptLimit = 5_000
}

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
              TimeZone(identifier: event.timeZoneIdentifier) != nil else { return false }
        if let erased = defaults.object(forKey: erasedKey) as? Date,
           event.occurredAt <= erased || event.targetDate <= erased { return false }
        return !(defaults.stringArray(forKey: key) ?? []).contains(event.id.uuidString)
    }

    func record(_ event: WatchActionEnvelope) {
        var receipts = defaults.stringArray(forKey: key) ?? []
        receipts.append(event.id.uuidString)
        defaults.set(receipts, forKey: key)
    }
}

import Foundation
import os

/// What Zoon last actually scheduled, and how that went.
///
/// The missing half of `ScheduleReconciliation`. Deciding whether a schedule
/// needs cancelling requires knowing what is currently scheduled, and neither
/// `UNUserNotificationCenter` nor AlarmKit is a usable source for that here:
/// the notification centre's pending requests are queryable but say nothing
/// about *why* a request is absent, and `WakeAlarm` documents that AlarmKit's
/// own store is not consulted directly. So Zoon records its own intent, which
/// is also the only thing that can distinguish "nothing scheduled because
/// nothing should be" from "nothing scheduled because the request failed".
///
/// UserDefaults-backed for the same reason `NapStore` is: three dates and
/// three short strings, read in bulk, never queried into.
@MainActor
@Observable
final class ScheduleStateStore {

    /// The three things Zoon schedules. Separate slots rather than one
    /// combined record because they fail independently -- notifications can
    /// be authorised while AlarmKit is not, and the wake alarm has its own
    /// toggle on top of Smart Wake.
    enum Slot: String, CaseIterable, Sendable {
        case bedtime
        case wakeWindow
        case wakeAlarm

        var label: String {
            switch self {
            case .bedtime: "Bedtime reminder"
            case .wakeWindow: "Wake window"
            case .wakeAlarm: "Wake alarm"
            }
        }
    }

    struct Entry: Codable, Equatable, Sendable {
        /// The time Zoon believes is scheduled, or `nil` when nothing is.
        var scheduledFor: Date?
        var status: ScheduleStatus
        var updatedAt: Date

        static let none = Entry(scheduledFor: nil, status: .notScheduled, updatedAt: .distantPast)
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "ScheduleState")
    private static let key = "zoon.schedules.v1"

    private(set) var entries: [String: Entry] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Reading

    func entry(_ slot: Slot) -> Entry {
        entries[slot.rawValue] ?? .none
    }

    func scheduledFor(_ slot: Slot) -> Date? {
        entry(slot).scheduledFor
    }

    func status(_ slot: Slot) -> ScheduleStatus {
        entry(slot).status
    }

    // MARK: - Writing

    /// Records the outcome of a reconciliation pass for one slot.
    ///
    /// Status and scheduled time are written together, on purpose: the pair
    /// is the claim, and updating one without the other is how a row ends up
    /// saying "Scheduled" with no time or vice versa.
    func record(_ scheduledFor: Date?, status: ScheduleStatus, for slot: Slot, now: Date = .now) {
        let entry = Entry(scheduledFor: scheduledFor, status: status, updatedAt: now)
        guard entries[slot.rawValue] != entry else { return }
        entries[slot.rawValue] = entry
        persist()
    }

    func clearAll() {
        guard !entries.isEmpty else { return }
        entries = [:]
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(entries), forKey: Self.key)
        } catch {
            logger.error("Could not persist schedule state: \(error.localizedDescription, privacy: .public)")
        }
    }
}

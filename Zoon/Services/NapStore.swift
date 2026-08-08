import Foundation
import SwiftUI

/// Nap tracking.
///
/// Backed by `UserDefaults` rather than SwiftData: naps are a short list of two
/// dates each, read in bulk and never queried into. A `@Model` would be more
/// ceremony than the data deserves.
///
/// Naps feed `SleepNeed.napCreditMinutes`, which is why they're worth recording
/// at all — HealthKit rarely captures a 20-minute daytime nap, so without this
/// the app would overstate tonight's requirement.
@MainActor
@Observable
final class NapStore {

    struct Nap: Codable, Identifiable, Hashable, Sendable {
        let start: Date
        let end: Date
        var id: Date { start }
        var minutes: Double { end.timeIntervalSince(start) / 60 }
    }

    struct ActiveNap: Codable, Hashable, Sendable {
        let start: Date
        let targetMinutes: Int
    }

    private enum Key {
        static let naps = "zoon.naps"
        static let active = "zoon.naps.active"
    }

    private let defaults: UserDefaults

    private(set) var naps: [Nap] = []
    private(set) var activeNap: ActiveNap?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Control

    func start(targetMinutes: Int) {
        activeNap = ActiveNap(start: .now, targetMinutes: targetMinutes)
        persistActive()
    }

    func cancel() {
        activeNap = nil
        persistActive()
    }

    /// Ends the nap and records it.
    ///
    /// Naps under two minutes are discarded rather than logged — a mis-tap
    /// shouldn't put a 4-second "nap" into the sleep-need calculation.
    func finish() {
        guard let active = activeNap else { return }
        let nap = Nap(start: active.start, end: .now)
        if nap.minutes >= 2 {
            naps.append(nap)
            persistNaps()
        }
        activeNap = nil
        persistActive()
    }

    // MARK: - Queries

    func recent(days: Int) -> [Nap] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return naps.filter { $0.start >= cutoff }.sorted { $0.start > $1.start }
    }

    /// Total nap minutes on a given calendar day — what `SleepNeed` credits.
    func minutes(on date: Date) -> Double {
        let calendar = Calendar.current
        return naps
            .filter { calendar.isDate($0.start, inSameDayAs: date) }
            .reduce(0) { $0 + $1.minutes }
    }

    /// Nap minutes on the day preceding a night, which is the credit that
    /// applies to that night's need.
    func minutesBefore(night: Date) -> Double {
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: night) ?? night
        return minutes(on: previousDay)
    }

    func deleteAll() {
        naps = []
        activeNap = nil
        persistNaps()
        persistActive()
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: Key.naps),
           let decoded = try? JSONDecoder().decode([Nap].self, from: data) {
            // Trim to a rolling year so this can't grow without bound.
            let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
            naps = decoded.filter { $0.start >= cutoff }
        }
        if let data = defaults.data(forKey: Key.active),
           let decoded = try? JSONDecoder().decode(ActiveNap.self, from: data) {
            // A nap "in progress" from more than 4 hours ago means the app was
            // killed mid-nap. Discard rather than resurrect a stale timer.
            if Date.now.timeIntervalSince(decoded.start) < 4 * 3600 {
                activeNap = decoded
            } else {
                defaults.removeObject(forKey: Key.active)
            }
        }
    }

    private func persistNaps() {
        defaults.set(try? JSONEncoder().encode(naps), forKey: Key.naps)
    }

    private func persistActive() {
        if let activeNap {
            defaults.set(try? JSONEncoder().encode(activeNap), forKey: Key.active)
        } else {
            defaults.removeObject(forKey: Key.active)
        }
    }
}

extension NapStore {
    /// Preview instance with a scratch defaults suite so previews can't write
    /// into the real nap log.
    static var preview: NapStore {
        let store = NapStore(defaults: UserDefaults(suiteName: "com.zoon.sleep.previews.naps") ?? .standard)
        store.deleteAll()
        store.naps = [
            Nap(start: .now.addingTimeInterval(-3600 * 26), end: .now.addingTimeInterval(-3600 * 26 + 1200)),
            Nap(start: .now.addingTimeInterval(-3600 * 50), end: .now.addingTimeInterval(-3600 * 50 + 1800))
        ]
        return store
    }
}

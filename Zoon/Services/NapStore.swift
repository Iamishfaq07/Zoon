import Foundation
import SwiftUI
import os
#if canImport(ActivityKit)
import ActivityKit
#endif

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
        startLiveActivity()
    }

    func cancel() {
        activeNap = nil
        persistActive()
        endLiveActivity()
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
        endLiveActivity()
    }

    // MARK: - Live Activity

    private let logger = Logger(subsystem: "com.zoon.sleep", category: "NapStore")

    /// Puts the nap countdown on the Lock Screen and in the Dynamic Island.
    ///
    /// Deliberately fire-and-forget: a nap timer that fails to start an
    /// activity should still be a working nap timer. Every failure path here
    /// logs and returns rather than surfacing anything.
    private func startLiveActivity() {
        #if canImport(ActivityKit)
        guard let nap = activeNap else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities are disabled; nap runs without one")
            return
        }

        let attributes = NapActivityAttributes(
            targetMinutes: nap.targetMinutes,
            startedAt: nap.start
        )
        let state = NapActivityAttributes.ContentState(
            endsAt: attributes.endDate,
            progress: 0
        )

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: attributes.endDate.addingTimeInterval(300)),
                pushType: nil
            )
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    private func endLiveActivity() {
        #if canImport(ActivityKit)
        // Dismiss immediately rather than leaving it to the default policy:
        // once the nap is over the card is stale, and a stale countdown on the
        // Lock Screen is worse than no countdown.
        for activity in Activity<NapActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
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
        endLiveActivity()
    }

    /// Merges naps from a backup, keyed on start time.
    ///
    /// Merge rather than replace: restoring a backup onto a device that has
    /// been recording since shouldn't discard the newer nights.
    /// - Returns: how many were actually added.
    @discardableResult
    func importNaps(_ imported: [Nap]) -> Int {
        let existing = Set(naps.map(\.start))
        let fresh = imported.filter { !existing.contains($0.start) }
        guard !fresh.isEmpty else { return 0 }
        naps.append(contentsOf: fresh)
        naps.sort { $0.start < $1.start }
        persistNaps()
        return fresh.count
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

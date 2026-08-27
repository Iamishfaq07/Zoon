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

        /// When the nap is meant to end.
        ///
        /// Persisted rather than always recomputed from `start` and
        /// `targetMinutes`, because this is the instant a system wake was
        /// scheduled against. Recomputing it would let a later change to how
        /// a target is derived silently move an in-flight nap's end away from
        /// the alarm that was already set.
        ///
        /// Optional so a nap persisted by a build predating this field still
        /// decodes -- `targetEnd` falls back for those.
        var targetEndAt: Date?

        var targetEnd: Date {
            targetEndAt ?? start.addingTimeInterval(Double(targetMinutes) * 60)
        }
    }

    /// A nap whose target passed while Zoon was not running, and whose real
    /// end time is therefore unknown.
    ///
    /// Deliberately not resolved automatically. `finish()` recorded
    /// `end: .now` unconditionally, and its only caller was a button -- so
    /// opening the app two hours after a twenty-minute nap and tapping stop
    /// logged a two-hour nap. That fed `SleepNeed.napCreditMinutes` and
    /// silently cancelled most of tonight's requirement, from a number the
    /// user never observed. Zoon asks instead.
    struct PendingNap: Codable, Hashable, Sendable {
        let start: Date
        let targetMinutes: Int
        let targetEnd: Date
        /// When Zoon noticed. Not the nap's end -- only the earliest moment
        /// the nap is known to have already been over.
        let noticedAt: Date
    }

    /// What `reconcile` did.
    enum ReconcileOutcome: Equatable, Sendable {
        /// No nap, or one still within its target.
        case none
        /// Closed without asking, clamped to the target.
        case finished(Nap)
        /// Too long past the target to guess. Awaiting the user.
        case needsConfirmation(PendingNap)
        /// Unrecoverably stale. Dropped rather than invented.
        case discarded
    }

    /// A nap shorter than this is a mis-tap, not a nap.
    static let minimumMinutes = 2.0

    /// How far past the target a nap can be closed without asking.
    ///
    /// Fifteen minutes covers the ordinary case -- the alarm went off, the
    /// user surfaced a few minutes later -- without covering "the app was
    /// closed all afternoon".
    static let graceMinutes = 15.0

    /// Beyond this past the target, what happened is unknowable and the
    /// entry is dropped. Four hours matches the bound `load()` already
    /// applied, except that this reports it rather than deleting silently.
    static let staleHours = 4.0

    private enum Key {
        static let naps = "zoon.naps"
        static let active = "zoon.naps.active"
        static let pending = "zoon.naps.pending"
    }

    private let defaults: UserDefaults

    private(set) var naps: [Nap] = []
    private(set) var activeNap: ActiveNap?
    /// A nap awaiting the user's answer about when it actually ended. See
    /// `PendingNap`.
    private(set) var pendingNap: PendingNap?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Control

    /// - Parameter now: injectable so a test can drive the clock. Production
    ///   callers use the default.
    func start(targetMinutes: Int, now: Date = .now) {
        activeNap = ActiveNap(
            start: now,
            targetMinutes: targetMinutes,
            targetEndAt: now.addingTimeInterval(Double(targetMinutes) * 60)
        )
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
    /// Naps under `minimumMinutes` are discarded rather than logged — a
    /// mis-tap shouldn't put a 4-second "nap" into the sleep-need
    /// calculation.
    ///
    /// The end is clamped to `graceMinutes` past the target. Overshooting by
    /// a few minutes is ordinary and recorded as-is; overshooting by an hour
    /// means the app was not in front of anyone, and the elapsed time is not
    /// evidence of sleep. `reconcile` handles the larger overruns properly,
    /// but this is the floor under the button itself so no single path can
    /// record an afternoon as a nap.
    /// - Returns: the recorded nap, or `nil` if it was too short to keep.
    @discardableResult
    func finish(now: Date = .now) -> Nap? {
        guard let active = activeNap else { return nil }
        let latestDefensibleEnd = active.targetEnd.addingTimeInterval(Self.graceMinutes * 60)
        let nap = Nap(start: active.start, end: min(now, latestDefensibleEnd))
        var recorded: Nap?
        if nap.minutes >= Self.minimumMinutes {
            naps.append(nap)
            persistNaps()
            recorded = nap
        }
        activeNap = nil
        persistActive()
        endLiveActivity()
        return recorded
    }

    // MARK: - Reconciliation

    /// Brings the stored nap state in line with the clock.
    ///
    /// Call on foreground and on appear. This is what replaces depending on
    /// `NapView`'s one-second `Task`: that loop only ever computed a progress
    /// ring, never ended anything, and it does not exist while the view is
    /// off screen — so before this, a nap simply never ended on its own.
    @discardableResult
    func reconcile(now: Date = .now) -> ReconcileOutcome {
        guard let active = activeNap else { return .none }
        let targetEnd = active.targetEnd
        guard now > targetEnd else { return .none }

        activeNap = nil
        persistActive()
        endLiveActivity()

        if now <= targetEnd.addingTimeInterval(Self.graceMinutes * 60) {
            // Clamped to the target, not to `now`. The timer was set for
            // `targetMinutes` and nothing observed more than that.
            let nap = Nap(start: active.start, end: targetEnd)
            if nap.minutes >= Self.minimumMinutes {
                naps.append(nap)
                persistNaps()
            }
            return .finished(nap)
        }

        if now <= targetEnd.addingTimeInterval(Self.staleHours * 3600) {
            let pending = PendingNap(
                start: active.start,
                targetMinutes: active.targetMinutes,
                targetEnd: targetEnd,
                noticedAt: now
            )
            pendingNap = pending
            persistPending()
            return .needsConfirmation(pending)
        }

        return .discarded
    }

    /// Records a pending nap as having run exactly to its target — the
    /// conservative answer, and the one the UI offers first.
    @discardableResult
    func acceptPendingAtTarget() -> Nap? {
        guard let pending = pendingNap else { return nil }
        return resolvePending(actualEnd: pending.targetEnd)
    }

    /// Records a pending nap with an end the user supplied.
    ///
    /// Clamped to the target: a user correcting the record downward is
    /// giving Zoon information, while one pushing it past the target is
    /// describing sleep nothing measured.
    @discardableResult
    func resolvePending(actualEnd: Date) -> Nap? {
        guard let pending = pendingNap else { return nil }
        let end = min(actualEnd, pending.targetEnd)
        pendingNap = nil
        persistPending()
        let nap = Nap(start: pending.start, end: end)
        guard nap.minutes >= Self.minimumMinutes else { return nil }
        naps.append(nap)
        persistNaps()
        return nap
    }

    /// Drops a pending nap without recording anything. "I don't remember" is
    /// a legitimate answer, and a guess is worse than a gap.
    func discardPending() {
        pendingNap = nil
        persistPending()
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
    ///
    /// - Parameter timeZone: The timezone `date`'s calendar day should be
    ///   read in. Defaults to the device's current one, which is correct
    ///   for "today" but not for a historical night -- a caller matching
    ///   naps against a specific stored night should pass that night's own
    ///   `SleepNightFeatures.timeZone` instead, the same way
    ///   `SleepDataCoordinator.deduplicatedNapMinutes`/`napIntervals(before:)`
    ///   do, otherwise which calendar day a nap counts toward can shift by a
    ///   day after the user travels.
    func minutes(on date: Date, timeZone: TimeZone = .current) -> Double {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return naps
            .filter { calendar.isDate($0.start, inSameDayAs: date) }
            .reduce(0) { $0 + $1.minutes }
    }

    /// Nap minutes on the day preceding a night, which is the credit that
    /// applies to that night's need. See `minutes(on:timeZone:)` for why
    /// `timeZone` matters.
    func minutesBefore(night: Date, timeZone: TimeZone = .current) -> Double {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let previousDay = calendar.date(byAdding: .day, value: -1, to: night) ?? night
        return minutes(on: previousDay, timeZone: timeZone)
    }

    func deleteAll() {
        naps = []
        activeNap = nil
        // Pending naps are user data too. Leaving one behind would have the
        // Delete Everything screen prompt about a nap after promising to
        // leave nothing.
        pendingNap = nil
        persistNaps()
        persistActive()
        persistPending()
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
        if let data = defaults.data(forKey: Key.pending),
           let decoded = try? JSONDecoder().decode(PendingNap.self, from: data) {
            pendingNap = decoded
        }
        if let data = defaults.data(forKey: Key.active),
           let decoded = try? JSONDecoder().decode(ActiveNap.self, from: data) {
            // Restored regardless of age. `reconcile` decides what a nap
            // whose target has passed becomes -- closed at target, awaiting
            // confirmation, or dropped -- so the age bound that used to live
            // here now reports itself instead of deleting in silence.
            activeNap = decoded
        }
    }

    private func persistNaps() {
        defaults.set(try? JSONEncoder().encode(naps), forKey: Key.naps)
    }

    private func persistPending() {
        if let pendingNap {
            defaults.set(try? JSONEncoder().encode(pendingNap), forKey: Key.pending)
        } else {
            defaults.removeObject(forKey: Key.pending)
        }
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

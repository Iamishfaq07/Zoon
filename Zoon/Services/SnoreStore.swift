import Foundation

/// Persists only the derived per-night minutes — never audio, never a
/// waveform, never anything raw. See `SnoreDetector` for why.
///
/// `UserDefaults`, matching `NapStore`: a short list of small structs, not
/// worth a SwiftData model and a schema migration.
@MainActor
@Observable
final class SnoreStore {

    struct NightSummary: Codable, Identifiable, Hashable, Sendable {
        let date: Date
        let monitoredMinutes: Double
        let snoreMinutes: Double
        /// Stable identity for the night this summary describes, in the
        /// timezone it was recorded in — see `NightKey`.
        ///
        /// Optional, and that is the migration: summaries written before
        /// night identity existed have no key and never can, because the
        /// recording timezone was never stored alongside them. Backfilling
        /// one from the device's *current* timezone would invent a fact —
        /// wrong for anyone who has since travelled — so those rows keep
        /// matching by `date`, exactly as they always have. This is the same
        /// mechanism `JournalEntry.nightKey` uses for the same reason.
        let nightKey: String?
        /// The timezone the recording happened in. `nil` on pre-migration
        /// rows, for the same reason as `nightKey`.
        let timezoneIdentifier: String?

        init(
            date: Date,
            monitoredMinutes: Double,
            snoreMinutes: Double,
            nightKey: String? = nil,
            timezoneIdentifier: String? = nil
        ) {
            self.date = date
            self.monitoredMinutes = monitoredMinutes
            self.snoreMinutes = snoreMinutes
            self.nightKey = nightKey
            self.timezoneIdentifier = timezoneIdentifier
        }

        /// Prefers the night key so a row keeps one identity even if the
        /// device's timezone moves under it; falls back to the instant for
        /// pre-migration rows, which is what identified them before.
        var id: String { nightKey ?? "date:\(date.timeIntervalSince1970)" }

        var snorePercent: Int {
            guard monitoredMinutes > 0 else { return 0 }
            return Int((snoreMinutes / monitoredMinutes * 100).rounded())
        }
    }

    /// Whether two summaries describe the same night.
    ///
    /// Uses `nightKey` only when *both* sides have one. A missing key means
    /// "recorded before we tracked this", not "a different night" — treating
    /// it as the latter would let an old row duplicate against its own
    /// replacement. Those fall back to the same-calendar-day comparison that
    /// has always matched them, with its known travel-day weakness intact but
    /// no worse than before.
    static func isSameNight(_ a: NightSummary, _ b: NightSummary) -> Bool {
        if let aKey = a.nightKey, let bKey = b.nightKey { return aKey == bKey }
        return Calendar.current.isDate(a.date, inSameDayAs: b.date)
    }

    private(set) var nights: [NightSummary] = []

    private let defaults: UserDefaults
    private static let key = "zoon.snore.nights"
    /// Kept lean on purpose — this is a supplementary estimate, not a metric
    /// the rest of the app builds baselines from.
    private let maxStored = 30

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([NightSummary].self, from: data) {
            nights = decoded
        }
    }

    func record(_ summary: NightSummary) {
        nights.removeAll { Self.isSameNight($0, summary) }
        nights.append(summary)
        persist()
    }

    var mostRecent: NightSummary? { nights.last }

    func deleteAll() {
        nights = []
        defaults.removeObject(forKey: Self.key)
    }

    /// Used by the centralized data lifecycle even when no snore screen (and
    /// therefore no `SnoreStore` instance) currently exists.
    static func erasePersistedData(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    @discardableResult
    func importSummaries(_ imported: [NightSummary]) -> Int {
        // Pairwise rather than a `Set` of days: matching now depends on both
        // sides (key-to-key, or day-to-day when either lacks a key), which a
        // single hashable value can't express. `maxStored` is 30, so the
        // quadratic scan is bounded and trivial.
        let fresh = imported.filter { candidate in
            !nights.contains { Self.isSameNight($0, candidate) }
        }
        guard !fresh.isEmpty else { return 0 }

        nights.append(contentsOf: fresh)
        persist()
        return fresh.count
    }

    private func persist() {
        nights.sort { $0.date < $1.date }
        if nights.count > maxStored { nights.removeFirst(nights.count - maxStored) }
        defaults.set(try? JSONEncoder().encode(nights), forKey: Self.key)
    }
}

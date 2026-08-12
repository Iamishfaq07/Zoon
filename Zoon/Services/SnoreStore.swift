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

        var id: Date { date }
        var snorePercent: Int {
            guard monitoredMinutes > 0 else { return 0 }
            return Int((snoreMinutes / monitoredMinutes * 100).rounded())
        }
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
        nights.removeAll { Calendar.current.isDate($0.date, inSameDayAs: summary.date) }
        nights.append(summary)
        nights.sort { $0.date < $1.date }
        if nights.count > maxStored { nights.removeFirst(nights.count - maxStored) }
        defaults.set(try? JSONEncoder().encode(nights), forKey: Self.key)
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
        let existingDays = Set(nights.map {
            Calendar.current.startOfDay(for: $0.date)
        })
        let fresh = imported.filter {
            !existingDays.contains(Calendar.current.startOfDay(for: $0.date))
        }
        guard !fresh.isEmpty else { return 0 }

        nights.append(contentsOf: fresh)
        nights.sort { $0.date < $1.date }
        if nights.count > maxStored { nights.removeFirst(nights.count - maxStored) }
        defaults.set(try? JSONEncoder().encode(nights), forKey: Self.key)
        return fresh.count
    }
}

import Foundation
import Observation

/// Local persistence for the optional functional check. These observations
/// are never folded into Sleep Intelligence or presented as a diagnosis.
@MainActor @Observable
final class AlertnessCheckStore {
    struct Result: Codable, Identifiable, Equatable {
        let id: UUID
        let date: Date
        let medianReactionMilliseconds: Int
        let lapses: Int
        let subjectiveAlertness: Int
    }

    private(set) var results: [Result] = []
    private let defaults: UserDefaults
    private let key = "zoon.alertnessCheck.results.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([Result].self, from: data) {
            results = decoded.sorted { $0.date > $1.date }
        }
    }

    func save(reactions: [TimeInterval], subjectiveAlertness: Int, date: Date = .now) {
        guard reactions.count >= 4 else { return }
        let milliseconds = reactions.map { $0 * 1_000 }.sorted()
        let median = milliseconds[milliseconds.count / 2]
        let result = Result(
            id: UUID(), date: date,
            medianReactionMilliseconds: Int(median.rounded()),
            lapses: milliseconds.filter { $0 >= 500 }.count,
            subjectiveAlertness: min(5, max(1, subjectiveAlertness))
        )
        results.insert(result, at: 0)
        results = Array(results.prefix(90))
        if let encoded = try? JSONEncoder().encode(results) { defaults.set(encoded, forKey: key) }
    }

    func deleteAll() {
        results = []
        defaults.removeObject(forKey: key)
    }
}

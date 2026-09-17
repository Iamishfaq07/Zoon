import Foundation
import Observation

/// Local persistence for the optional functional check. These observations
/// are never folded into Sleep Intelligence or presented as a diagnosis.
///
/// **Why the storage key moved to v2.** The v1 record held a median, a lapse
/// count and a self-rating, and nothing else — no spread, no false starts, no
/// time since waking. Those cannot be reconstructed from what was kept, so v1
/// results are read once and carried forward with the new fields *absent*
/// rather than defaulted: a zero IQR would claim a perfectly consistent run,
/// and a zero false-start count would claim there were none, neither of which
/// anybody measured. Absent is the honest shape, and `AlertnessCheck` already
/// refuses to compare sessions that cannot be compared.
@MainActor @Observable
final class AlertnessCheckStore {

    private(set) var sessions: [AlertnessCheck.Session] = []

    private let defaults: UserDefaults
    private let key = "zoon.alertnessCheck.results.v2"
    private let legacyKey = "zoon.alertnessCheck.results.v1"

    /// The shape v1 wrote. Kept only to read the old records in.
    private struct LegacyResult: Codable {
        let id: UUID
        let date: Date
        let medianReactionMilliseconds: Int
        let lapses: Int
        let subjectiveAlertness: Int
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([AlertnessCheck.Session].self, from: data) {
            sessions = decoded.sorted { $0.date > $1.date }
        } else if let data = defaults.data(forKey: legacyKey),
                  let legacy = try? JSONDecoder().decode([LegacyResult].self, from: data) {
            sessions = legacy
                .map {
                    AlertnessCheck.Session(
                        id: $0.id,
                        date: $0.date,
                        medianMilliseconds: Double($0.medianReactionMilliseconds),
                        // Not measured by v1, and absent rather than zero: a
                        // zero IQR claims a perfectly consistent run and a
                        // zero false-start count claims there were none.
                        iqrMilliseconds: nil,
                        lapses: $0.lapses,
                        falseStarts: 0,
                        trials: nil,
                        minutesSinceWaking: nil,
                        subjectiveAlertness: $0.subjectiveAlertness
                    )
                }
                .sorted { $0.date > $1.date }
            persist()
        }
    }

    /// Records a run, and returns what can be said about it — which for the
    /// first several runs is deliberately nothing.
    ///
    /// Returns `nil` when the run was too short to store, so the caller can
    /// tell the person it was not saved instead of showing them a tick. The
    /// old version dropped short runs silently while the screen said "Saved on
    /// this device".
    @discardableResult
    func save(
        reactions: [TimeInterval],
        falseStarts: Int = 0,
        subjectiveAlertness: Int?,
        wakeTime: Date? = nil,
        date: Date = .now
    ) -> AlertnessCheck.Outcome? {
        guard let session = AlertnessCheck.session(
            reactions: reactions,
            falseStarts: falseStarts,
            subjectiveAlertness: subjectiveAlertness,
            wakeTime: wakeTime,
            date: date
        ) else { return nil }

        sessions.insert(session, at: 0)
        sessions = Array(sessions.prefix(90))
        persist()
        return AlertnessCheck.evaluate(latest: session, history: sessions)
    }

    func deleteAll() {
        sessions = []
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: legacyKey)
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(encoded, forKey: key)
    }
}

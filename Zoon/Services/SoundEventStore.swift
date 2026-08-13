import Foundation

/// Persists the categorized events from the most recent overnight listening
/// session. Same storage shape as `SnoreStore` -- `UserDefaults`, capped, no
/// SwiftData -- and the same privacy floor: only each event's derived
/// (identifier, time, confidence) survives, never audio.
@MainActor
@Observable
final class SoundEventStore {

    private(set) var recentEvents: [SoundEvent] = []

    private let defaults: UserDefaults
    private static let key = "zoon.soundEvents.recent"
    /// This is "what happened last night," not a running log across many
    /// sessions -- one night's worth of events is comfortably under this,
    /// and the cap exists only to bound a session that ran unexpectedly long.
    private let maxStored = 200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([SoundEvent].self, from: data) {
            recentEvents = decoded
        }
    }

    /// Replaces the stored list with one session's events -- there is only
    /// ever "the most recent session," not a history to append to.
    func record(_ events: [SoundEvent]) {
        recentEvents = events.count > maxStored
            ? Array(events.suffix(maxStored))
            : events
        defaults.set(try? JSONEncoder().encode(recentEvents), forKey: Self.key)
    }

    func deleteAll() {
        recentEvents = []
        defaults.removeObject(forKey: Self.key)
    }

    /// Used by the centralized data lifecycle even when no snore screen (and
    /// therefore no `SoundEventStore` instance) currently exists.
    static func erasePersistedData(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

import Foundation

/// Lightweight overnight checkpoint. No audio, only derived intervals.
///
/// Written every few minutes so a crash or iOS kill does not erase the night.
/// On relaunch the UI says monitoring ended unexpectedly — it does not pretend
/// the session continued.
struct SnoreCheckpoint: Codable, Equatable, Sendable {
    var sessionID: UUID
    var startedAt: Date
    var lastCheckpoint: Date
    var monitoredSeconds: Double
    var snoreSeconds: Double
    var heuristicSeconds: Double
    var classifierSeconds: Double
    var interruptionGaps: Int
    var classifierAvailable: Bool
    var windows: [SnoreClassificationWindow]
    var unexpectedEnd: Bool

    static let persistInterval: TimeInterval = 180
    static let storageKey = "zoon.snore.checkpoint"

    func save(defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.storageKey)
    }

    static func load(defaults: UserDefaults = .standard) -> SnoreCheckpoint? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(SnoreCheckpoint.self, from: data)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    var monitoredCaption: String {
        let total = Int(monitoredSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    func unexpectedEndMessage() -> String {
        let clock = lastCheckpoint.formatted(date: .omitted, time: .shortened)
        return "Last night's Snore Check ended unexpectedly at \(clock). \(monitoredCaption) of monitoring was preserved."
    }
}

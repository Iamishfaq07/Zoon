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
    var gaps: [SnoreMonitoringGap]
    var classifierAvailable: Bool
    var windows: [SnoreClassificationWindow]
    var unexpectedEnd: Bool
    var timezoneIdentifier: String?
    var nightKey: String?
    var monitoringQuality: SnoreMonitoringConfidence?

    static let persistInterval: TimeInterval = 180
    static let storageKey = "zoon.snore.checkpoint"

    enum CodingKeys: String, CodingKey {
        case sessionID, startedAt, lastCheckpoint, monitoredSeconds, snoreSeconds
        case heuristicSeconds, classifierSeconds, interruptionGaps, gaps
        case classifierAvailable, windows, unexpectedEnd
        case timezoneIdentifier, nightKey, monitoringQuality
    }

    init(
        sessionID: UUID,
        startedAt: Date,
        lastCheckpoint: Date,
        monitoredSeconds: Double,
        snoreSeconds: Double,
        heuristicSeconds: Double,
        classifierSeconds: Double,
        interruptionGaps: Int,
        gaps: [SnoreMonitoringGap] = [],
        classifierAvailable: Bool,
        windows: [SnoreClassificationWindow],
        unexpectedEnd: Bool,
        timezoneIdentifier: String? = nil,
        nightKey: String? = nil,
        monitoringQuality: SnoreMonitoringConfidence? = nil
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.lastCheckpoint = lastCheckpoint
        self.monitoredSeconds = monitoredSeconds
        self.snoreSeconds = snoreSeconds
        self.heuristicSeconds = heuristicSeconds
        self.classifierSeconds = classifierSeconds
        self.interruptionGaps = interruptionGaps
        self.gaps = gaps
        self.classifierAvailable = classifierAvailable
        self.windows = windows
        self.unexpectedEnd = unexpectedEnd
        self.timezoneIdentifier = timezoneIdentifier
        self.nightKey = nightKey
        self.monitoringQuality = monitoringQuality
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        lastCheckpoint = try c.decode(Date.self, forKey: .lastCheckpoint)
        monitoredSeconds = try c.decode(Double.self, forKey: .monitoredSeconds)
        snoreSeconds = try c.decode(Double.self, forKey: .snoreSeconds)
        heuristicSeconds = try c.decode(Double.self, forKey: .heuristicSeconds)
        classifierSeconds = try c.decode(Double.self, forKey: .classifierSeconds)
        interruptionGaps = try c.decode(Int.self, forKey: .interruptionGaps)
        gaps = try c.decodeIfPresent([SnoreMonitoringGap].self, forKey: .gaps) ?? []
        classifierAvailable = try c.decode(Bool.self, forKey: .classifierAvailable)
        windows = try c.decode([SnoreClassificationWindow].self, forKey: .windows)
        unexpectedEnd = try c.decode(Bool.self, forKey: .unexpectedEnd)
        timezoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timezoneIdentifier)
        nightKey = try c.decodeIfPresent(String.self, forKey: .nightKey)
        monitoringQuality = try c.decodeIfPresent(SnoreMonitoringConfidence.self, forKey: .monitoringQuality)
    }

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

    var snoreCaption: String {
        let minutes = Int((snoreSeconds / 60).rounded())
        return "\(minutes)m estimated snoring"
    }

    var interruptionDuration: TimeInterval {
        gaps.reduce(0) { $0 + $1.duration }
    }

    func unexpectedEndMessage() -> String {
        let clock = lastCheckpoint.formatted(date: .omitted, time: .shortened)
        return "Monitoring ended unexpectedly at \(clock). \(monitoredCaption) monitored, \(snoreCaption)."
    }
}

import Foundation

struct PersonalSetup: Codable, Equatable, Sendable {
    var scoreLight = false
    var plans: [SleepPlan] = []
    var scenes: [Scene] = []
    var routine = Routine()
    var session: RoutineSession?
    var repairs: [Repair] = []
    var trip: SavedTrip?

    struct SavedTrip: Codable, Equatable, Sendable {
        var destination: String
        var departure: Date
        var arrival: Date
    }
    struct SleepPlan: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        var name: String
        var timeZoneIdentifier: String
        var bedtimeMinute: Int
        var wakeMinute: Int
        /// Calendar weekdays of the bedtime. Empty means one date only.
        var weekdays: Set<Int>
        var firstDate: Date
        var enabled = true

        func nextWindow(after now: Date) -> DateInterval? {
            guard enabled, let zone = TimeZone(identifier: timeZoneIdentifier),
                  (0..<1440).contains(bedtimeMinute), (0..<1440).contains(wakeMinute) else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            for offset in -1...8 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                      day >= calendar.startOfDay(for: firstDate),
                      weekdays.isEmpty ? calendar.isDate(day, inSameDayAs: firstDate) : weekdays.contains(calendar.component(.weekday, from: day)),
                      let bed = calendar.date(bySettingHour: bedtimeMinute / 60, minute: bedtimeMinute % 60, second: 0, of: day) else { continue }
                guard let wakeDay = wakeMinute <= bedtimeMinute
                    ? calendar.date(byAdding: .day, value: 1, to: day)
                    : day else { continue }
                guard let wake = calendar.date(bySettingHour: wakeMinute / 60, minute: wakeMinute % 60, second: 0, of: wakeDay), wake > now, wake > bed else { continue }
                return DateInterval(start: bed, end: wake)
            }
            return nil
        }
    }
    struct Layer: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        var sound: String
        var level: Double
    }
    struct Scene: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        var name: String
        var layers: [Layer]
    }
    struct Routine: Codable, Equatable, Sendable {
        var minutes = 30
        var breathing = true
        var voice = true
        var haptics = false
        var sceneID: UUID?
    }
    struct RoutineSession: Codable, Equatable, Sendable {
        var startedAt: Date
        var deadline: Date
        var pausedSeconds: TimeInterval?
        func remaining(at now: Date) -> TimeInterval { max(0, pausedSeconds ?? deadline.timeIntervalSince(now)) }
    }
    struct Repair: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        var nightKey: String
        var recordedAt = Date.now
        var reason: String
        /// Excludes this night from comparative history, preserving the original.
        var excluded = true
    }

    func nextWindow(after date: Date = .now) -> DateInterval? {
        plans.compactMap { $0.nextWindow(after: date) }.min { $0.start < $1.start }
    }

    var isValid: Bool {
        (1...180).contains(routine.minutes)
        && scenes.allSatisfy { (1...3).contains($0.layers.count) && $0.layers.allSatisfy { $0.level.isFinite && (0...1).contains($0.level) } }
        && plans.allSatisfy { TimeZone(identifier: $0.timeZoneIdentifier) != nil && (0..<1440).contains($0.bedtimeMinute) && (0..<1440).contains($0.wakeMinute) && $0.weekdays.allSatisfy { (1...7).contains($0) } }
    }
}

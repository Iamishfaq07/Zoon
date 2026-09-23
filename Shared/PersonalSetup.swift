import Foundation

struct PersonalSetup: Codable, Equatable, Sendable {
    var scoreLight = false
    var plans: [SleepPlan] = []
    var scenes: [Scene] = []
    var routine = Routine()
    var session: RoutineSession?
    var repairs: [Repair] = []
    var trip: SavedTrip?
    /// Nights the person switched reminders off for, keyed by the morning
    /// the night ends on (`PersonalSetup.nightKey(forWake:)`). Optional so a
    /// setup saved before this existed still decodes.
    var skippedReminderNights: [String]?

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

    /// "2026-09-24" for the night ending on the morning of the 24th, in the
    /// calendar given. The morning, because that is how the runway names a
    /// night and how the person thinks of "Thursday's early start".
    static func nightKey(forWake wake: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: wake)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func isSkipped(wake: Date, calendar: Calendar = .current) -> Bool {
        (skippedReminderNights ?? []).contains(Self.nightKey(forWake: wake, calendar: calendar))
    }

    /// Switches reminders for one night on or off, and forgets skips for
    /// mornings already past so the list cannot grow without bound.
    mutating func setSkipped(_ skipped: Bool, wake: Date, now: Date = .now, calendar: Calendar = .current) {
        let key = Self.nightKey(forWake: wake, calendar: calendar)
        let today = Self.nightKey(forWake: now, calendar: calendar)
        var keys = Set(skippedReminderNights ?? []).filter { $0 >= today }
        if skipped { keys.insert(key) } else { keys.remove(key) }
        skippedReminderNights = keys.isEmpty ? nil : keys.sorted()
    }

    /// Sets one night's bed and wake as a one-night plan, replacing any
    /// one-night plan already covering that night. Standing weekday plans
    /// are left alone: this is "just this night".
    ///
    /// - Parameter morning: the morning the night ends on. The bed falls the
    ///   evening before, or that morning's own date when it is after
    ///   midnight (a bed clock time at or before the wake's).
    mutating func setNightPlan(
        bedMinute: Int,
        wakeMinute: Int,
        morning: Date,
        name: String,
        calendar: Calendar = .current
    ) {
        clearNightPlan(morning: morning, calendar: calendar)
        guard bedMinute != wakeMinute,
              (0..<1440).contains(bedMinute), (0..<1440).contains(wakeMinute) else { return }
        let morningDay = calendar.startOfDay(for: morning)
        let bedDay = bedMinute > wakeMinute
            ? (calendar.date(byAdding: .day, value: -1, to: morningDay) ?? morningDay)
            : morningDay
        plans.append(SleepPlan(
            name: name,
            timeZoneIdentifier: calendar.timeZone.identifier,
            bedtimeMinute: bedMinute,
            wakeMinute: wakeMinute,
            weekdays: [],
            firstDate: bedDay
        ))
    }

    /// Removes the one-night plans for the night ending on `morning`.
    mutating func clearNightPlan(morning: Date, calendar: Calendar = .current) {
        let morningDay = calendar.startOfDay(for: morning)
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: morningDay) ?? morningDay
        plans.removeAll { plan in
            guard plan.weekdays.isEmpty, let window = plan.nextWindow(after: dayBefore) else { return false }
            return calendar.isDate(window.end, inSameDayAs: morningDay)
        }
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

import Foundation

/// Deterministic mapping from a Coach utterance to a safe tool.
///
/// Read-only tools can run without confirmation. Anything that writes a
/// journal row, starts a nap, schedules an alarm, or opens Tomorrow requires
/// an explicit confirm. The catalog never invents metric values — engines
/// remain the source of truth at execution time.
enum CoachToolCatalog {

    enum Kind: String, Hashable, Sendable {
        case getSleepScore
        case getRecovery
        case getShortfall
        case getEnergy
        case getTonight
        case getTomorrow
        case logCaffeine
        case startNap
        case prepareTomorrow
        case setAlarm

        var requiresConfirmation: Bool {
            switch self {
            case .logCaffeine, .startNap, .prepareTomorrow, .setAlarm: true
            default: false
            }
        }

        var summary: String {
            switch self {
            case .getSleepScore: "Read last night's Sleep Intelligence."
            case .getRecovery: "Read morning Recovery."
            case .getShortfall: "Read sleep shortfall."
            case .getEnergy: "Read Energy now."
            case .getTonight: "Read tonight's sleep window."
            case .getTomorrow: "Read the Tomorrow plan, if one exists."
            case .logCaffeine: "Log caffeine after you confirm."
            case .startNap: "Start a nap after you confirm."
            case .prepareTomorrow: "Open Tomorrow after you confirm the time."
            case .setAlarm: "Propose a wake alarm after you confirm."
            }
        }
    }

    struct Call: Equatable, Sendable {
        let kind: Kind
        let proposedMinutes: Int?
        let confirmationPrompt: String?
    }

    static func interpret(_ utterance: String) -> Call? {
        let q = utterance.lowercased()

        // Read-only first. These branches cannot write anything, so letting a
        // question fall into a confirm-to-write tool is the only ordering
        // mistake that can do harm -- and it was the one being made: a bare
        // "tomorrow" was matched ahead of every read branch, so "what does my
        // recovery look like tomorrow" opened the Tomorrow planner and
        // `.getTomorrow` was declared but returned by nothing.
        if matches(q, ["sleep score", "sleep intelligence", "how did i sleep"]) {
            return Call(kind: .getSleepScore, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["recovery"]) {
            return Call(kind: .getRecovery, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["shortfall", "sleep debt", "behind on sleep"]) {
            return Call(kind: .getShortfall, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["energy now", "body battery", "how alert"]) {
            return Call(kind: .getEnergy, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["sleep window", "tonight's plan", "when should i sleep", "bedtime"]) {
            return Call(kind: .getTonight, proposedMinutes: nil, confirmationPrompt: nil)
        }
        // Phrased as a question about the plan, never a bare "tomorrow":
        // the word alone appears in every utterance that wants the planner
        // *opened*, which is a write.
        if matches(q, ["tomorrow plan", "plan for tomorrow", "what's tomorrow", "whats tomorrow", "my tomorrow"]) {
            return Call(kind: .getTomorrow, proposedMinutes: nil, confirmationPrompt: nil)
        }

        // Writes. Each one confirms before it does anything.
        if matches(q, ["log coffee", "log caffeine", "had coffee", "coffee at"]) {
            let minutes = parseTimeOfDayMinutes(q)
            let label = minutes.map { "Log caffeine at approximately \(clock(minutes: $0))?" }
                ?? "Log caffeine for today?"
            return Call(kind: .logCaffeine, proposedMinutes: minutes, confirmationPrompt: label)
        }
        if isNapRequest(q) {
            let minutes = parseNapMinutes(q) ?? 25
            return Call(
                kind: .startNap,
                proposedMinutes: minutes,
                confirmationPrompt: "Start a \(minutes)-minute nap?"
            )
        }
        if matches(q, ["prepare me", "get me ready", "big day", "meeting tomorrow", "presentation tomorrow"]) {
            let minutes = parseTimeOfDayMinutes(q)
            let prompt = minutes.map { "Prepare you for \(clock(minutes: $0)) tomorrow?" }
                ?? "Open Tomorrow and set a morning start time?"
            return Call(kind: .prepareTomorrow, proposedMinutes: minutes, confirmationPrompt: prompt)
        }
        if matches(q, ["set my alarm", "set alarm", "wake me"]) {
            return Call(kind: .setAlarm, proposedMinutes: nil, confirmationPrompt: "Set an alarm from tonight's plan?")
        }
        return nil
    }

    /// Whether this is a request to *start* a nap.
    ///
    /// Fixed phrases could not see "start a 25 minute nap": the duration sits
    /// between "start a" and "nap", so none of "start a nap", "start nap",
    /// "nap for" or "take a nap" is a substring of it. The word plus an
    /// intent verb matches the same sentences without caring what is wedged
    /// in the middle, and still declines "how was my nap".
    private static func isNapRequest(_ q: String) -> Bool {
        guard wholeWord("nap", in: q) else { return false }
        return matches(q, ["start", "take", "have a", "set a", "nap for"])
    }

    /// `phrase` as a whole word, so "nap" is not found inside "kidnapping"
    /// or "snap".
    private static func wholeWord(_ phrase: String, in q: String) -> Bool {
        guard let pattern = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
        ) else { return q.contains(phrase) }
        return pattern.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)) != nil
    }

    private static func matches(_ q: String, _ keys: [String]) -> Bool {
        keys.contains { q.contains($0) }
    }

    /// Minutes from midnight for a spoken time, or `nil`.
    ///
    /// The regex always captured the minute group and the old version never
    /// read it, so "8:30" resolved to 8:00 -- on a feature whose headline
    /// example is a manual 8:30 start. Returning minutes rather than an hour
    /// removes the lossy step entirely: every caller wanted minutes and was
    /// multiplying an hour by 60 to get them.
    ///
    /// A bare hour with no am/pm is still ambiguous and is left as written;
    /// the confirmation prompt is what catches a wrong reading, which is the
    /// whole reason these tools confirm.
    private static func parseTimeOfDayMinutes(_ q: String) -> Int? {
        let pattern = #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
              let hourRange = Range(match.range(at: 1), in: q),
              var hour = Int(q[hourRange]) else { return nil }

        let minute: Int = {
            guard let r = Range(match.range(at: 2), in: q), let value = Int(q[r]) else { return 0 }
            return (0...59).contains(value) ? value : 0
        }()
        let meridiem: String? = {
            guard let r = Range(match.range(at: 3), in: q) else { return nil }
            return String(q[r])
        }()
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        guard (0...23).contains(hour) else { return nil }
        return hour * 60 + minute
    }

    private static func parseNapMinutes(_ q: String) -> Int? {
        let pattern = #"\b(\d{1,2})\s*(minute|min|minutes)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
              let r = Range(match.range(at: 1), in: q),
              let minutes = Int(q[r]) else { return nil }
        return min(90, max(10, minutes))
    }

    private static func clock(minutes: Int) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%d:%02d", minutes / 60, minutes % 60)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

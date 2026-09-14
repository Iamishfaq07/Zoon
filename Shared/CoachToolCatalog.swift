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

        if matches(q, ["log coffee", "log caffeine", "had coffee", "coffee at"]) {
            let hour = parseHour(q)
            let label = hour.map { "Log caffeine at approximately \(clock($0))?" } ?? "Log caffeine for today?"
            return Call(kind: .logCaffeine, proposedMinutes: hour.map { $0 * 60 }, confirmationPrompt: label)
        }
        if matches(q, ["start a nap", "start nap", "nap for", "take a nap"]) {
            let minutes = parseNapMinutes(q) ?? 25
            return Call(
                kind: .startNap,
                proposedMinutes: minutes,
                confirmationPrompt: "Start a \(minutes)-minute nap?"
            )
        }
        if matches(q, ["prepare me", "tomorrow", "big day", "meeting tomorrow", "presentation tomorrow"]) {
            let hour = parseHour(q)
            let prompt = hour.map { "Prepare you for \($0 == 0 ? "12" : "\($0)") o'clock tomorrow?" }
                ?? "Open Tomorrow and set a morning start time?"
            return Call(kind: .prepareTomorrow, proposedMinutes: hour.map { $0 * 60 }, confirmationPrompt: prompt)
        }
        if matches(q, ["set my alarm", "set alarm", "wake me"]) {
            return Call(kind: .setAlarm, proposedMinutes: nil, confirmationPrompt: "Set an alarm from tonight's plan?")
        }
        if matches(q, ["sleep window", "tonight's plan", "when should i sleep", "bedtime"]) {
            return Call(kind: .getTonight, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["shortfall", "sleep debt", "behind on sleep"]) {
            return Call(kind: .getShortfall, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["recovery"]) {
            return Call(kind: .getRecovery, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["energy now", "body battery", "how alert"]) {
            return Call(kind: .getEnergy, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["sleep score", "sleep intelligence", "how did i sleep"]) {
            return Call(kind: .getSleepScore, proposedMinutes: nil, confirmationPrompt: nil)
        }
        return nil
    }

    private static func matches(_ q: String, _ keys: [String]) -> Bool {
        keys.contains { q.contains($0) }
    }

    private static func parseHour(_ q: String) -> Int? {
        let pattern = #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
              let hourRange = Range(match.range(at: 1), in: q),
              var hour = Int(q[hourRange]) else { return nil }
        let meridiem: String? = {
            guard let r = Range(match.range(at: 3), in: q) else { return nil }
            return String(q[r])
        }()
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        return (0...23).contains(hour) ? hour : nil
    }

    private static func parseNapMinutes(_ q: String) -> Int? {
        let pattern = #"\b(\d{1,2})\s*(minute|min|minutes)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
              let r = Range(match.range(at: 1), in: q),
              let minutes = Int(q[r]) else { return nil }
        return min(90, max(10, minutes))
    }

    private static func clock(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else {
            return "\(hour):00"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

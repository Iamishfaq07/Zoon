import Foundation

/// Deterministic mapping from a Coach utterance to a safe tool.
///
/// Read-only tools can run without confirmation. Anything that writes a
/// journal row, starts a nap, schedules an alarm, or opens Tomorrow requires
/// an explicit confirm. The catalog never invents metric values — engines
/// remain the source of truth at execution time.
enum CoachToolCatalog {

    /// `CaseIterable` so the tests can enumerate every tool rather than
    /// restating a list beside this one. The confirmation contract's whole
    /// point is to catch a tool added without being classified, and a
    /// hand-written list in the test cannot do that — it was the list that
    /// would need updating.
    enum Kind: String, Hashable, Sendable, CaseIterable {
        case getSleepScore
        case getLastNightSummary
        case getSleepDuration
        case getRecovery
        case getShortfall
        case getEnergy
        case getMovement
        case getTonight
        case getTomorrow
        case getFatigueContext
        case getTrainingContext
        case logCaffeine
        case startNap
        case prepareTomorrow
        case setAlarm

        /// Whether running this tool changes anything.
        ///
        /// Written as an explicit switch with no `default`, so a tool added to
        /// the enum fails to compile until somebody says which side of the
        /// line it is on. The previous `default: false` silently made every
        /// new tool a read.
        var changesState: Bool {
            switch self {
            case .logCaffeine, .startNap, .prepareTomorrow, .setAlarm:
                true
            case .getSleepScore, .getLastNightSummary, .getSleepDuration, .getRecovery, .getShortfall, .getEnergy,
                 .getMovement, .getTonight, .getTomorrow, .getFatigueContext, .getTrainingContext:
                false
            }
        }

        var requiresConfirmation: Bool { changesState }

        var summary: String {
            switch self {
            case .getSleepScore: "Read last night's Sleep Intelligence."
            case .getLastNightSummary: "Read a short last-night summary."
            case .getSleepDuration: "Read last night's sleep duration."
            case .getRecovery: "Read morning Recovery."
            case .getShortfall: "Read sleep shortfall."
            case .getEnergy: "Read Energy now."
            case .getMovement: "Read today's movement against your usual day."
            case .getTonight: "Read tonight's sleep window."
            case .getTomorrow: "Read the Tomorrow plan, if one exists."
            case .getFatigueContext: "Read current signals that may relate to feeling tired."
            case .getTrainingContext: "Read Recovery, Energy and Load together."
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
        if matches(q, [
            "how much did i sleep", "how long did i sleep", "how long was i asleep",
            "sleep duration", "time asleep"
        ]) {
            return Call(kind: .getSleepDuration, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, [
            "sleep score", "sleep intelligence", "how did i sleep"
        ]) {
            return Call(kind: .getSleepScore, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["last night summary", "summarise last night", "summarize last night", "what happened last night", "how was last night"]) {
            return Call(kind: .getLastNightSummary, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["why am i tired", "why do i feel tired", "feeling tired", "feel tired"]) {
            return Call(kind: .getFatigueContext, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["should i train", "train today", "should i work out", "workout today", "ready to train"]) {
            return Call(kind: .getTrainingContext, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["recovery", "how am i doing", "how recovered"]) {
            return Call(kind: .getRecovery, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["shortfall", "sleep debt", "behind on sleep"]) {
            return Call(kind: .getShortfall, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, ["energy now", "body battery", "how alert", "how much energy", "energy do i have", "enough energy", "energy"]) {
            return Call(kind: .getEnergy, proposedMinutes: nil, confirmationPrompt: nil)
        }
        // Movement is asked about in the app's own words ("moved", "steps")
        // and in the words people actually use. Checked before the sleep
        // window, because "have I moved enough today" contains none of that
        // block's phrases but "active" appears in questions about both.
        if matches(q, ["steps", "how much have i moved", "moved today", "movement today", "active today"]) {
            return Call(kind: .getMovement, proposedMinutes: nil, confirmationPrompt: nil)
        }
        if matches(q, [
            "sleep window", "tonight's plan", "tonights plan", "when should i sleep",
            "bedtime", "what should i do tonight", "what should i focus"
        ]) {
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
            let minutes = parseTimeOfDayMinutes(q, bareHour: .afternoon)
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
            let minutes = parseTimeOfDayMinutes(q, bareHour: .morning)
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
    /// How to read a bare hour with no am/pm on it.
    ///
    /// "Log coffee at 5" and "prepare me for 9" both give a number and no
    /// meridiem, and they mean opposite halves of the day. Reading both as
    /// written — which is what this did — resolved the caffeine one to 05:00,
    /// so the brief's own example ("Log coffee at 5." → "Log caffeine at
    /// approximately 5:00 PM?") came out as five in the morning and was
    /// recorded as `.caffeine` rather than `.caffeineLate`, understating the
    /// exposure it exists to capture.
    ///
    /// The defaults are per call site rather than global because the contexts
    /// genuinely differ: caffeine at a bare hour is the afternoon, a morning
    /// commitment at a bare hour is the morning, and `latestMorningEventHour`
    /// would reject a 9 PM "meeting" anyway. A wrong guess is visible and
    /// cancellable — everything using this is behind a confirmation — which
    /// is what makes choosing the more likely reading the right call rather
    /// than refusing to guess.
    enum BareHour {
        case morning, afternoon
    }

    private static func parseTimeOfDayMinutes(_ q: String, bareHour: BareHour) -> Int? {
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
        // Only 1 through 11 are ambiguous: 0, 12 and 13-23 already say which
        // half of the day they are in.
        if meridiem == nil, bareHour == .afternoon, (1...11).contains(hour) { hour += 12 }
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

    /// The hour past which caffeine is the `.caffeineLate` behaviour rather
    /// than `.caffeine`. Matches that tag's own label, "Caffeine after 4pm".
    static let lateCaffeineHour = 16

    /// Internal rather than private: the runner formats the same proposed
    /// time back to the person after acting on it, and two spellings of the
    /// same clock in one exchange reads as two different times.
    static func clock(minutes: Int) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%d:%02d", minutes / 60, minutes % 60)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

import Foundation

/// Converts a short journal sentence into proposed, editable observations.
/// Nothing produced here is evidence until the user confirms it in the UI.
enum NaturalJournalParser {
    enum Confidence: String, Codable, Sendable { case high, medium, low }

    struct Proposal: Identifiable, Equatable {
        let tag: BehaviorTag
        let state: BehaviorObservationState
        let matchedText: String
        let confidence: Confidence
        var id: String { tag.rawValue }
    }

    private struct Rule { let tag: BehaviorTag; let phrases: [String] }

    private static let rules: [Rule] = [
        Rule(tag: .caffeine, phrases: ["coffee", "coffees", "caffeine", "espresso", "tea"]),
        Rule(tag: .lateMeal, phrases: ["ate late", "eat late", "late meal", "late dinner", "dinner late"]),
        Rule(tag: .largeDinner, phrases: ["large dinner", "big dinner", "heavy meal"]),
        Rule(tag: .hardTraining, phrases: ["hard workout", "hard training", "gym", "workout", "long run", "intense workout", "exercised"]),
        Rule(tag: .alcohol, phrases: ["alcohol", "beer", "wine", "cocktail", "drinks"]),
        Rule(tag: .stressfulDay, phrases: ["stressful", "stressed", "rough day", "anxious"]),
        Rule(tag: .travelled, phrases: ["travelled", "traveled", "flight", "jet lag", "hotel"]),
        Rule(tag: .screenBeforeBed, phrases: ["screen in bed", "phone in bed", "watched tv", "late screen"]),
        Rule(tag: .readBeforeBed, phrases: ["read before bed", "reading in bed"]),
        Rule(tag: .morningDaylight, phrases: ["morning light", "morning daylight", "outside this morning", "morning walk"]),
        Rule(tag: .sauna, phrases: ["sauna"]),
        Rule(tag: .coldPlunge, phrases: ["cold plunge", "ice bath"]),
        Rule(tag: .magnesium, phrases: ["magnesium"]),
        Rule(tag: .sleepAid, phrases: ["sleep aid", "sleeping pill", "melatonin"]),
        Rule(tag: .sick, phrases: ["feeling sick", "felt sick", "unwell", "fever", "cold symptoms"]),
        Rule(tag: .sharedBed, phrases: ["shared bed", "partner stayed"]),
        Rule(tag: .coolRoom, phrases: ["cool room", "cold bedroom"]),
        Rule(tag: .hydrated, phrases: ["hydrated", "lots of water"]),
        Rule(tag: .restDay, phrases: ["rest day"])
    ]

    private static let negations = ["no", "didn't", "without", "avoided", "skipped", "not"]

    static func proposals(from text: String) -> [Proposal] {
        let lower = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        var output: [Proposal] = []
        for rule in rules {
            guard var phrase = rule.phrases.first(where: { range(of: $0, in: lower) != nil }) else { continue }
            // "Tea but no coffee" still contains a positive caffeine source;
            // choose the positive entity instead of letting the negated coffee
            // token erase the tea observation.
            if rule.tag == .caffeine, phrase == "coffee", range(of: "tea", in: lower) != nil, state(for: phrase, in: lower) == .no,
               state(for: "tea", in: lower) == .yes { phrase = "tea" }
            let state = state(for: phrase, in: lower)
            let timing = timeNear(phrase: phrase, in: lower)
            let isLateCaffeine = rule.tag == .caffeine && (lower.contains("late coffee") || lower.contains("coffee late") || timing.map { $0 >= 15 } == true)
            let tag: BehaviorTag = isLateCaffeine ? .caffeineLate : rule.tag
            let confidence: Confidence = timing != nil || state == .no ? .high : (phrase.count > 5 ? .medium : .low)
            output.append(Proposal(tag: tag, state: state, matchedText: timing.map { "\(phrase) at \(formatHour($0))" } ?? phrase, confidence: confidence))
        }
        if output.contains(where: { $0.tag == .caffeineLate }) { output.removeAll { $0.tag == .caffeine } }
        return output
    }

    /// Whole-word occurrence of `phrase`, so "tea" is not found inside
    /// "steak" or "steady" and "drinks" is not found inside "soft-drinks-ish"
    /// coinages. Plain substring matching proposed caffeine for a steady day.
    private static func range(of phrase: String, in text: String) -> Range<String.Index>? {
        text.range(
            of: "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b",
            options: .regularExpression
        )
    }

    private static func state(for phrase: String, in text: String) -> BehaviorObservationState {
        guard let index = range(of: phrase, in: text)?.lowerBound else { return .unknown }
        let tokens = String(text[..<index]).split(separator: " ").suffix(5).map(String.init)
        let hasDidNot = tokens.contains("did") && tokens.contains("not")
        return negations.contains(where: { tokens.contains($0) }) || hasDidNot ? .no : .yes
    }

    /// "at 4pm", "around 4:30 PM", "after 3": the connective, then the hour,
    /// then optional minutes and meridiem, as capture groups. The previous
    /// pattern re-split the matched text on spaces to find the hour, which
    /// broke the moment there was no space before "pm".
    private static let timePattern = try? NSRegularExpression(
        pattern: #"\b(?:at|around|after)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
    )

    /// Finds a clock hour only when it is attached to the matched entity.
    /// An isolated "after 3" elsewhere can never create caffeine.
    private static func timeNear(phrase: String, in text: String) -> Int? {
        guard let matched = range(of: phrase, in: text) else { return nil }
        let tail = String(text[matched.upperBound...].prefix(24))
        guard let timePattern = Self.timePattern,
              let match = timePattern.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
              let hourRange = Range(match.range(at: 1), in: tail),
              let hour = Int(tail[hourRange]), (0...23).contains(hour) else { return nil }
        let meridiem = Range(match.range(at: 3), in: tail).map { String(tail[$0]) }
        switch meridiem {
        case "am": return hour == 12 ? 0 : hour
        case "pm": return hour == 12 ? 12 : hour + 12
        default: return hour
        }
    }

    private static func formatHour(_ hour: Int) -> String { hour >= 12 ? "\(hour == 12 ? 12 : hour - 12)pm" : "\(hour)am" }
}

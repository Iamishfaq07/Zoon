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
        Rule(tag: .lateMeal, phrases: ["ate late", "late meal", "late dinner", "dinner late"]),
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
            guard let phrase = rule.phrases.first(where: { lower.contains($0) }) else { continue }
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

    private static func state(for phrase: String, in text: String) -> BehaviorObservationState {
        guard let index = text.range(of: phrase)?.lowerBound else { return .unknown }
        let tokens = String(text[..<index]).split(separator: " ").suffix(5).map(String.init)
        let hasDidNot = tokens.contains("did") && tokens.contains("not")
        return negations.contains(where: { tokens.contains($0) }) || hasDidNot ? .no : .yes
    }

    /// Finds a clock hour only when it is attached to the matched entity.
    /// An isolated "after 3" elsewhere can never create caffeine.
    private static func timeNear(phrase: String, in text: String) -> Int? {
        guard let range = text.range(of: phrase) else { return nil }
        let tail = String(text[range.upperBound...].prefix(24))
        let pattern = #"(?:at|around|after)\s+(\d{1,2})(?::\d{2})?\s*(am|pm)?"#
        guard let match = tail.range(of: pattern, options: .regularExpression) else { return nil }
        let value = String(tail[match])
        guard let clock = value.split(separator: " ").dropFirst().first,
              let hour = Int(clock.split(separator: ":").first ?? "") else { return nil }
        return value.contains("pm") ? (hour == 12 ? 12 : hour + 12) : hour
    }

    private static func formatHour(_ hour: Int) -> String { hour >= 12 ? "\(hour == 12 ? 12 : hour - 12)pm" : "\(hour)am" }
}

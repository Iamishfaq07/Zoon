import Foundation

/// Converts a short journal sentence into proposed structured observations.
/// Nothing produced here is evidence until the user confirms it in the UI.
enum NaturalJournalParser {
    struct Proposal: Identifiable, Equatable {
        let tag: BehaviorTag
        let matchedText: String
        var id: String { tag.rawValue }
    }

    private struct Rule {
        let tag: BehaviorTag
        let phrases: [String]
    }

    private static let rules: [Rule] = [
        Rule(tag: .caffeineLate, phrases: ["late coffee", "coffee late", "caffeine late", "after 3 pm", "after 3pm", "after 4 pm", "after 4pm", "tea late"]),
        Rule(tag: .caffeine, phrases: ["coffee", "coffees", "caffeine", "espresso", "tea"]),
        Rule(tag: .lateMeal, phrases: ["ate late", "late meal", "late dinner", "dinner late"]),
        Rule(tag: .largeDinner, phrases: ["large dinner", "big dinner", "heavy meal"]),
        Rule(tag: .hardTraining, phrases: ["hard workout", "hard training", "gym", "long run", "intense workout"]),
        Rule(tag: .lateTraining, phrases: ["trained late", "late workout", "gym late", "evening workout"]),
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
        Rule(tag: .restDay, phrases: ["rest day", "no workout"])
    ]

    static func proposals(from text: String) -> [Proposal] {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var matches: [Proposal] = rules.compactMap { (rule: Rule) -> Proposal? in
            guard let phrase = rule.phrases.first(where: { normalized.contains($0) }) else { return nil }
            return Proposal(tag: rule.tag, matchedText: phrase)
        }
        // A specifically timed caffeine observation subsumes the generic one.
        // Keeping both would ask the user to confirm the same drink twice.
        if matches.contains(where: { $0.tag == .caffeineLate }) {
            matches.removeAll { $0.tag == .caffeine }
        }
        return matches
    }
}

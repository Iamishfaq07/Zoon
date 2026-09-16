import Foundation

/// Converts a short journal sentence into proposed, editable observations.
/// Nothing produced here is evidence until the user confirms it in the UI.
enum NaturalJournalParser {
    enum Confidence: String, Codable, Sendable { case high, medium, low }

    struct Proposal: Identifiable, Equatable {
        let behavior: BehaviorID
        /// What to call it. A custom behaviour has no enum case to ask.
        let label: String
        let state: BehaviorObservationState
        let matchedText: String
        let confidence: Confidence
        var id: String { behavior.identifier }
        /// The built-in tag, when this proposal is about one.
        var tag: BehaviorTag? { behavior.builtIn }
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

    /// Proposals for the built-in vocabulary plus whatever the person has
    /// named themselves.
    ///
    /// An earlier version took a `customNames:` parameter and ended with
    /// `_ = customNames`: it accepted the list and discarded it, so the
    /// natural-language box silently ignored every custom signal while
    /// appearing to support them. That parameter was removed rather than
    /// filled in, because parsing was not the missing piece —
    /// `Proposal.tag` was a closed enum with no custom case, and
    /// `setBehavior` recorded against that same enum, so there was nowhere
    /// to *store* a confirmed custom observation even if the text had been
    /// understood. `BehaviorID` is that missing piece, so the parameter is
    /// back, and now it does something.
    ///
    /// Nothing here is evidence. A proposal is a suggestion the person
    /// confirms or discards, which is the rule for built-ins too: Zoon never
    /// silently saves an inferred behaviour.
    static func proposals(
        from text: String,
        catalog: BehaviorCatalog = .builtInOnly
    ) -> [Proposal] {
        let lower = text.folding(options: .diacriticInsensitive, locale: .current).lowercased()
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
            output.append(Proposal(
                behavior: tag.behaviorID,
                label: tag.label,
                state: state,
                matchedText: timing.map { "\(phrase) at \(formatHour($0))" } ?? phrase,
                confidence: confidence
            ))
        }
        if output.contains(where: { $0.tag == .caffeineLate }) { output.removeAll { $0.tag == .caffeine } }

        // Custom signals match on their own name, whole-word, the same rule
        // the built-in phrases use -- so a signal called "tea" is not found
        // inside "steady". Confidence is never `.high` from a name alone:
        // the person chose the word, Zoon has no vocabulary around it, and a
        // single mention is a weaker signal than a matched phrase with a time
        // attached.
        for behavior in catalog.custom where behavior.isActive {
            let name = behavior.name
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
            guard !name.isEmpty, range(of: name, in: lower) != nil else { continue }
            let state = state(for: name, in: lower)
            guard state != .unknown else { continue }
            output.append(Proposal(
                behavior: behavior.behaviorID,
                label: behavior.name,
                state: state,
                matchedText: name,
                confidence: state == .no ? .medium : .low
            ))
        }
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

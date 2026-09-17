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

        // MARK: - Structured detail (§9)
        //
        // Read out of the sentence and carried as a *proposal*, never saved
        // from here. "Had two coffees, last one around 5" used to become
        // `caffeine = yes` and the hour was spent on a display string nothing
        // could query -- see `BehaviorDetail` for why that costs the dose and
        // timing curves §18 asks for.

        /// How many, when the sentence said. `nil` for "had coffee", which is
        /// an unknown number of coffees and not one.
        let quantity: Double?
        /// The word the sentence counted in, where there was one.
        let unit: String?
        /// The clock time, as minutes since midnight, when the sentence
        /// attached one to *this* entity. Minutes rather than a `Date`
        /// because the parser reads text and does not know which night this
        /// will be filed under, nor in which timezone -- anchoring happens at
        /// confirmation, in `detail(onNightDay:calendar:)`.
        let eventClockMinutes: Int?
        /// How hard, where the sentence used a word for it.
        let intensity: Double?

        var id: String { behavior.identifier }
        /// The built-in tag, when this proposal is about one.
        var tag: BehaviorTag? { behavior.builtIn }

        init(
            behavior: BehaviorID,
            label: String,
            state: BehaviorObservationState,
            matchedText: String,
            confidence: Confidence,
            quantity: Double? = nil,
            unit: String? = nil,
            eventClockMinutes: Int? = nil,
            intensity: Double? = nil
        ) {
            self.behavior = behavior
            self.label = label
            self.state = state
            self.matchedText = matchedText
            self.confidence = confidence
            self.quantity = quantity
            self.unit = unit
            self.eventClockMinutes = eventClockMinutes
            self.intensity = intensity
        }

        /// The detail as it would be stored, anchored onto the night it
        /// belongs to.
        ///
        /// The clock time is placed on `nightDay` in `calendar`'s timezone,
        /// which must be the night's own -- re-deriving the hour later, in
        /// whatever zone the phone is in then, is exactly the bug
        /// `SleepNightFeatures.timeZoneIdentifier` exists to prevent.
        ///
        /// An evening time belongs to the evening *before* the morning a
        /// night is filed under, the same rule `Fixture.night` and
        /// `SleepEras` follow: "coffee at 5" on the night ending Tuesday
        /// morning was Monday at 17:00.
        func detail(onNightDay nightDay: Date, calendar: Calendar = .current) -> BehaviorDetail? {
            var eventTime: Date?
            if let eventClockMinutes {
                let hour = eventClockMinutes / 60
                let minute = eventClockMinutes % 60
                let day = hour >= 12
                    ? calendar.date(byAdding: .day, value: -1, to: nightDay) ?? nightDay
                    : nightDay
                // Components then verified, never `date(bySettingHour:…)`:
                // that call searches forward across days for a clock time the
                // day does not have, and returns an instant on a different
                // day rather than nil. See `MovementContext.comparableSlice`,
                // which documents the same trap at length.
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = hour
                components.minute = minute
                components.second = 0
                if let candidate = calendar.date(from: components),
                   calendar.component(.hour, from: candidate) == hour,
                   calendar.component(.minute, from: candidate) == minute {
                    eventTime = candidate
                }
            }
            let detail = BehaviorDetail(
                quantity: quantity, unit: unit, eventTime: eventTime, intensity: intensity
            )
            return detail.isEmpty ? nil : detail
        }
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

            // Structured detail, proposed and never saved from here. A `.no`
            // carries none: "no coffee" is an answer about whether, and
            // attaching a count or a time to it would be Zoon inventing
            // detail for an event that did not happen.
            let quantified = state == .yes ? quantityNear(phrase: phrase, in: lower) : nil
            let intensity = state == .yes && tag.takesIntensity ? intensityIn(lower) : nil

            output.append(Proposal(
                behavior: tag.behaviorID,
                label: tag.label,
                state: state,
                matchedText: timing.map { "\(phrase) at \(formatHour($0))" } ?? phrase,
                confidence: confidence,
                quantity: quantified?.0,
                unit: quantified?.1,
                eventClockMinutes: state == .yes ? clockMinutesNear(phrase: phrase, in: lower) : nil,
                intensity: intensity
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
            // Custom behaviours take detail on the same terms as built-ins.
            // Somebody who named a signal "chocolate" and writes "three
            // chocolates at 9" has said a quantity and a time, and dropping
            // them because Zoon did not supply the word would make custom
            // signals second-class exactly where §9 says they must not be.
            let quantified = state == .yes ? quantityNear(phrase: name, in: lower) : nil
            output.append(Proposal(
                behavior: behavior.behaviorID,
                label: behavior.name,
                state: state,
                matchedText: name,
                confidence: state == .no ? .medium : .low,
                quantity: quantified?.0,
                unit: quantified?.1,
                eventClockMinutes: state == .yes ? clockMinutesNear(phrase: name, in: lower) : nil
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
        clockMinutesNear(phrase: phrase, in: text, requiringUnambiguousHour: false)
            .map { $0 / 60 }
    }

    /// The same match, kept to the minute.
    ///
    /// `timeNear` throws the minutes away because it only ever fed an
    /// hour-granularity display string and a `>= 15` late-caffeine test.
    /// `BehaviorDetail.eventTime` is a real clock time somebody will read
    /// back, and rounding "around 4:30" to 4pm in storage would be Zoon
    /// deciding it knew better than the sentence.
    /// - Parameter requiringUnambiguousHour: when true, a bare hour with no
    ///   am/pm is refused rather than resolved.
    ///
    ///   "Last one around 5" means five in the afternoon to everybody who
    ///   writes it, and nothing in the sentence says so. Resolving it to 05:00
    ///   would store a morning coffee somebody had in the evening; resolving
    ///   it to 17:00 would be Zoon guessing, and a guess written into a dose
    ///   curve is indistinguishable from a measurement once it is there. So a
    ///   stored `eventTime` needs an explicit meridiem or an hour that can only
    ///   mean one thing (13 through 23, or a bare 0).
    ///
    ///   The lenient form stays for `timeNear`, which feeds the display string
    ///   and the late-caffeine heuristic. Both are suggestions the person is
    ///   looking at and can reject; neither is written down.
    private static func clockMinutesNear(
        phrase: String,
        in text: String,
        requiringUnambiguousHour: Bool = true
    ) -> Int? {
        guard let matched = range(of: phrase, in: text) else { return nil }
        let tail = String(text[matched.upperBound...].prefix(24))
        guard let timePattern = Self.timePattern,
              let match = timePattern.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
              let hourRange = Range(match.range(at: 1), in: tail),
              let rawHour = Int(tail[hourRange]), (0...23).contains(rawHour) else { return nil }

        let minute = Range(match.range(at: 2), in: tail)
            .flatMap { Int(tail[$0]) }
            .flatMap { (0...59).contains($0) ? $0 : nil } ?? 0

        let meridiem = Range(match.range(at: 3), in: tail).map { String(tail[$0]) }
        let hour: Int
        switch meridiem {
        case "am": hour = rawHour == 12 ? 0 : rawHour
        case "pm": hour = rawHour == 12 ? 12 : rawHour + 12
        default:
            // No meridiem. 13-23 can only be one time; 1-12 could be either.
            if requiringUnambiguousHour, (1...12).contains(rawHour) { return nil }
            hour = rawHour
        }
        guard (0...23).contains(hour) else { return nil }
        return hour * 60 + minute
    }

    /// Number words Zoon reads as counts.
    ///
    /// Stops at ten on purpose. Past that people write digits, and a longer
    /// table would start matching "one" inside "one of those days".
    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "couple": 2, "few": 3
    ]

    /// Intensity words, matched anywhere in the sentence.
    private static let intensityWords = [
        "easy", "light", "gentle", "moderate", "steady", "hard", "intense",
        "heavy", "brutal", "tough"
    ]

    /// How many of `phrase`, when the words immediately before it say so.
    ///
    /// Immediately before, and nowhere else: "two coffees" is a count, and a
    /// stray "two" in another clause is not. Returns the number and the word
    /// it counted, so "2 coffees" stores "coffees" rather than a unit Zoon
    /// chose for somebody.
    private static func quantityNear(phrase: String, in text: String) -> (Double, String)? {
        guard let matched = range(of: phrase, in: text) else { return nil }
        let head = String(text[..<matched.lowerBound])
        guard let last = head.split(separator: " ").last.map(String.init) else { return nil }
        let token = last.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !token.isEmpty else { return nil }

        if let digits = Double(token), digits > 0, digits < 100 {
            return (digits, phrase)
        }
        if let word = numberWords[token] {
            // "a coffee" and "an espresso" are grammar, not a count somebody
            // stated. Counting them as one would put every unquantified night
            // in the one-cup band, which is the fabricated-precision failure
            // `BehaviorDetail` exists to avoid.
            guard token != "a", token != "an" else { return nil }
            return (word, phrase)
        }
        return nil
    }

    /// The intensity word the sentence used, if any.
    private static func intensityIn(_ text: String) -> Double? {
        for word in intensityWords where range(of: word, in: text) != nil {
            return BehaviorDetail.intensity(forWord: word)
        }
        return nil
    }

    private static func formatHour(_ hour: Int) -> String { hour >= 12 ? "\(hour == 12 ? 12 : hour - 12)pm" : "\(hour)am" }
}

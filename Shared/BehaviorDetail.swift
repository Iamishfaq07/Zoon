import Foundation

/// The structured part of an observation: how much, when, how hard.
///
/// **What this is for.** "Had two coffees, last one around 5" and "coffee"
/// were the same stored row — `caffeine = yes` — and everything downstream saw
/// the same night. The parser already read the hour out of that sentence and
/// spent it on a display string ("coffee at 5pm") that nothing could query.
/// A sensitivity curve over caffeine *dose*, or over caffeine *timing*, has to
/// come from somewhere, and a yes/no cannot supply it.
///
/// **Every field is optional, and absent is not zero.** A night recorded as
/// "coffee" with no number is a night with an unknown number of coffees, not a
/// night with one. That distinction is the reason these are `Double?` rather
/// than defaulted: an engine that treats a missing dose as zero would put
/// every unquantified night in the control band and produce a curve out of
/// nothing.
///
/// **Nothing here is ever inferred and saved.** The parser proposes; the
/// person confirms or edits; only then is a detail written. There is no path
/// that stores a quantity somebody did not agree to, which matters more here
/// than for a yes/no: "two" is a specific claim about somebody's day, and a
/// wrong one silently poisons every curve built on it.
struct BehaviorDetail: Hashable, Sendable, Codable {

    /// How many. Cups, drinks, milligrams — `unit` says which.
    let quantity: Double?

    /// What `quantity` counts, as the person's own word for it where there is
    /// one. A free string rather than an enum because custom behaviours are
    /// the point: somebody counting "squares of chocolate" needs that to
    /// survive, and an enum would silently drop it.
    let unit: String?

    /// When it happened — the *last* occurrence where there were several,
    /// since that is the one that matters to a night's sleep.
    ///
    /// An absolute instant, anchored at confirmation time onto the night's own
    /// day in the night's own timezone. That is what makes it survive travel:
    /// re-deriving a clock hour later, in whatever zone the phone is in then,
    /// is the bug `SleepNightFeatures.timeZoneIdentifier` exists to prevent.
    let eventTime: Date?

    /// How hard, on 0–1, where the behaviour has a natural intensity and the
    /// person said something about it. A "hard leg session" is not a "light
    /// spin", and a workout observation that cannot tell them apart cannot
    /// support the workout-load curve §18 asks for.
    ///
    /// Deliberately not derived from heart rate or strain. Those are separate
    /// measurements with their own provenance; this is what the person said.
    let intensity: Double?

    init(
        quantity: Double? = nil,
        unit: String? = nil,
        eventTime: Date? = nil,
        intensity: Double? = nil
    ) {
        // A negative count is not a count, and a zero one is "it did not
        // happen" -- which is the state's job to say, not the quantity's.
        self.quantity = quantity.flatMap { $0 > 0 ? $0 : nil }
        self.unit = unit.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.eventTime = eventTime
        self.intensity = intensity.map { min(1, max(0, $0)) }
    }

    /// Whether there is anything here at all. An observation with an empty
    /// detail stores nothing, so a row cannot come to mean "quantified as
    /// nothing in particular".
    var isEmpty: Bool {
        quantity == nil && unit == nil && eventTime == nil && intensity == nil
    }

    /// Clock minutes since midnight, in the zone the event was anchored in.
    ///
    /// The form the sensitivity curves take. `calendar` must carry the night's
    /// own timezone — the same requirement `Statistics.clockMinutes` states,
    /// and for the same reason.
    func eventClockMinutes(calendar: Calendar) -> Double? {
        eventTime.map { Statistics.clockMinutes($0, calendar: calendar) }
    }

    /// A short, readable summary for a confirmation row: "2 coffees · 5:00 PM".
    ///
    /// `nil` when there is nothing to show, so a surface renders the plain
    /// behaviour name rather than a stray separator.
    func summary(calendar: Calendar = .current) -> String? {
        var parts: [String] = []
        if let quantity {
            let rounded = quantity.rounded()
            let number = quantity == rounded ? String(Int(rounded)) : String(format: "%.1f", quantity)
            parts.append(unit.map { "\(number) \($0)" } ?? number)
        }
        if let eventTime {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("jmm")
            parts.append(formatter.string(from: eventTime))
        }
        if let intensity {
            parts.append(Self.intensityLabel(intensity))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Words rather than a number, because 0.8 is not something anybody said.
    /// The person's own word is what was matched to get here; this maps back.
    static func intensityLabel(_ intensity: Double) -> String {
        switch intensity {
        case ..<0.34: "easy"
        case ..<0.67: "moderate"
        default: "hard"
        }
    }

    /// The intensity a word implies, or `nil` for a word that implies none.
    ///
    /// Three levels, not a scale. Anybody reading "hard" as 0.8 rather than
    /// 0.75 would be reading precision into a word that has none, and the
    /// bands `intensityLabel` maps back to are the only resolution claimed.
    static func intensity(forWord word: String) -> Double? {
        switch word.lowercased() {
        case "easy", "light", "gentle", "easy-going": 0.2
        case "moderate", "steady", "normal": 0.5
        case "hard", "intense", "heavy", "brutal", "tough": 0.85
        default: nil
        }
    }
}

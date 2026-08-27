import Foundation

extension Int {

    /// `5.pluralized("night")` → "5 nights"; `1.pluralized("night")` → "1 night".
    ///
    /// Irregular plurals pass the second form explicitly:
    /// `1.pluralized("entry", "entries")` → "1 entry".
    ///
    /// This exists because `count == 1 ? "" : "s"` was being retyped at every
    /// call site that needed it — and the sites where someone forgot are
    /// exactly the ones that shipped "1 of 1 nights" and "Restored 1 naps".
    /// A count and its noun travel together often enough to be one call
    /// rather than two interpolations that can drift apart.
    ///
    /// Deliberately not `String.localizedStringWithFormat` against a
    /// stringsdict: the app ships no localisations yet, and a stringsdict
    /// that exists only in English is more machinery to keep in sync than
    /// this replaces. If localisation lands, this is the single place that
    /// has to change.
    func pluralized(_ singular: String, _ plural: String? = nil) -> String {
        "\(self) \(self == 1 ? singular : plural ?? singular + "s")"
    }
}

extension String {

    /// Uppercases only the first character, leaving the rest alone --
    /// `capitalized` would turn "resting heart rate" into "Resting Heart
    /// Rate" mid-sentence.
    ///
    /// Lived as a `private extension` inside `NightDetective` until a second
    /// caller needed it. Kept here beside `pluralized` rather than copied:
    /// two private copies of the same three lines is how the two duplicate
    /// confidence enums that became `MetricConfidence` started, and a
    /// sentence-casing rule is exactly the kind of thing that has to stay
    /// consistent across every string the app renders.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

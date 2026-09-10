import Foundation

/// One question Coach should ask this week, derived from Cause Finder.
///
/// Duration is the pre-specified primary metric. The copy is a question,
/// never a cause.
struct WeeklyQuestion: Equatable, Sendable {
    let question: String
    let why: String
    let tagLabel: String?

    static func make(strongestTag: String?, deltaMinutes: Double?) -> WeeklyQuestion {
        guard let label = strongestTag, let delta = deltaMinutes else {
            return WeeklyQuestion(
                question: "Does a cool room change how long you sleep?",
                why: "Duration is the pre-specified metric. Not enough tagged nights yet to pick a sharper question.",
                tagLabel: nil
            )
        }
        let verb = delta >= 0 ? "lengthen" : "shorten"
        return WeeklyQuestion(
            question: "Does \(label.lowercased()) still \(verb) your nights?",
            why: "Duration is the only metric this question uses.",
            tagLabel: label
        )
    }
}

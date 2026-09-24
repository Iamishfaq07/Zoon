import Foundation

/// A cause the deterministic rules have already proved from tonight's data.
///
/// The audit's §7.1 concern: `likelyCause` used to be free text. The
/// numeric grounding check stops a model inventing *numbers*, but not a
/// cause -- "caffeine", "stress" -- that nothing measured. So the model no
/// longer writes the cause. It may only choose one of these, by `id`, and
/// the sentence shown is `observed`, which the rule wrote from the data.
struct InsightDriver: Hashable, Sendable {
    /// Stable identifier the model is allowed to return, e.g. "late-workout".
    let id: String
    /// The rule's own sentence about tonight's data. Rendered verbatim.
    let observed: String
}

/// What a generated `driverID` resolves to.
enum InsightDriverSelection: Equatable, Sendable {
    /// The model named no driver.
    case none
    /// One of tonight's eligible drivers.
    case driver(InsightDriver)
    /// An id that was not offered. The whole generation is rejected: a model
    /// that invents evidence once is not trusted for the rest of the card.
    case rejected(String)

    static let noneTokens: Set<String> = ["", "none", "null", "nil", "n/a"]

    static func resolve(_ raw: String, eligible: [InsightDriver]) -> InsightDriverSelection {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if noneTokens.contains(id) { return .none }
        if let match = eligible.first(where: { $0.id == id }) { return .driver(match) }
        return .rejected(id)
    }

    /// The block the prompt carries: the only ids the model may return.
    static func promptBlock(_ eligible: [InsightDriver]) -> String {
        guard !eligible.isEmpty else {
            return "Supported drivers: none. Set driverID to \"none\"."
        }
        let lines = eligible.map { "- \($0.id): \($0.observed)" }
        return "Supported drivers (set driverID to exactly one id, or \"none\"):\n" + lines.joined(separator: "\n")
    }
}

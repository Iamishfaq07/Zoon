import Foundation

/// The one decision about whether a Recovery score may be shown as a number.
///
/// **Why this exists.** The engine has had a real `MetricConfidence` for a
/// while, and the watch, the widgets and the complications already refuse to
/// state a score below `.insufficient` — `SleepSnapshot.canStateRecovery` is
/// that gate. The iPhone did not have one. Every ring, hero, brief and metric
/// grid read `recovery.percent` directly, so the same night that showed "—"
/// on the wrist showed a confident two-digit number on the phone.
///
/// The scenario that matters: sleep is recorded, HRV and resting heart rate
/// and respiration are all absent. Coverage is 20% — sleep alone — and the
/// weighted engine still returns a number, because the components that
/// remain re-normalise. It can legitimately compute 92. That 92 is a
/// restatement of how long someone slept, and printing it beside the word
/// "Recovery" claims something the data cannot support.
///
/// Every surface asks this type instead of deciding for itself.
enum RecoveryPresentationState: Equatable, Sendable {

    /// Show the number. Confidence rides along so a surface can qualify it.
    case available(score: Int, confidence: MetricConfidence)
    /// The model ran but on too little physiology to stand behind.
    case limited(reason: String)
    /// Not enough nights of personal history yet.
    case buildingBaseline(nights: Int, required: Int)
    /// No score at all.
    case unavailable

    /// The only state whose number may be drawn.
    var score: Int? {
        if case .available(let score, _) = self { return score }
        return nil
    }

    var isShowable: Bool { score != nil }

    /// What to show in place of the number.
    var placeholder: String {
        switch self {
        case .available(let score, _): "\(score)"
        case .limited: "Limited"
        case .buildingBaseline: "Building"
        case .unavailable: "—"
        }
    }

    /// The heading a detail view or hero uses.
    var title: String {
        switch self {
        case .available: "Recovery"
        case .limited: "Limited recovery data"
        case .buildingBaseline: "Building your baseline"
        case .unavailable: "Recovery unavailable"
        }
    }

    /// One sentence of explanation, or `nil` when the number speaks for
    /// itself at high confidence.
    var explanation: String? {
        switch self {
        case .available(_, let confidence):
            confidence == .high ? nil : confidence.label
        case .limited(let reason):
            reason
        case .buildingBaseline(let nights, let required):
            "\(nights) of \(required) nights. Recovery needs a personal baseline before it means anything."
        case .unavailable:
            "No recovery score for this day."
        }
    }
}

extension RecoveryScore {

    /// Resolves this score into what a surface is allowed to draw.
    ///
    /// Order matters: an insufficient baseline and insufficient coverage are
    /// different problems with different remedies — one resolves by waiting,
    /// the other may be a permission or a watch left on the nightstand — so
    /// the binding one is named rather than both collapsing to "limited".
    var presentation: RecoveryPresentationState {
        let baseline = Self.baselineConfidence(nightCount: baselineNightCount)
        let coverage = Self.coverageConfidence(percent: dataCompletenessPercent)

        if baseline == .insufficient {
            return .buildingBaseline(
                nights: baselineNightCount,
                required: Self.minimumBaselineNights
            )
        }
        if coverage == .insufficient {
            let missing = components.filter { !$0.isAvailable }.map(\.label)
            let reason = missing.isEmpty
                ? "Sleep data is available, but more physiological data is needed to estimate recovery reliably."
                : "Sleep data is available, but no \(missing.map { $0.lowercased() }.joined(separator: " or ")) last night. More physiological data is needed to estimate recovery reliably."
            return .limited(reason: reason)
        }
        return .available(score: percent, confidence: confidence)
    }
}

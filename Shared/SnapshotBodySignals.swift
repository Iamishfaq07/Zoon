import SwiftUI

/// Reads a snapshot's body-signal state once, for every surface that shows it.
///
/// The watch, the complications and the widgets each used to compare
/// `bodySignalsLabel` against the literal string "Nothing unusual" and treat a
/// match as reassurance. Three problems with that, all of which shipped:
///
/// 1. A snapshot written before the field existed decoded to exactly that
///    string, so every legacy payload asserted the user was fine.
/// 2. A user on night four has no baseline and produced the same string.
/// 3. A phone-only user with no HRV, resting heart rate or respiratory rate
///    produced it too — nothing was drifting because nothing was measured.
///
/// Only the first of the five states below is reassurance. The rest say, in
/// one place and one wording, that Zoon does not know yet.
struct SnapshotBodySignals {

    enum State: String {
        case building = "Building"
        case noData = "No data"
        case typical = "Typical"
        case watch = "Watch"
        case notable = "Notable"
        /// Written by a build that predates the state field.
        case unknown = ""
    }

    let state: State
    let headline: String

    init(snapshot: SleepSnapshot) {
        state = State(rawValue: snapshot.bodySignalsState) ?? .unknown
        headline = snapshot.bodySignalsLabel.isEmpty
            ? "No body-signal reading yet"
            : snapshot.bodySignalsLabel
    }

    /// Short enough for a complication or a watch row.
    var shortLabel: String {
        switch state {
        case .typical: "Typical"
        case .watch: "Watch"
        case .notable: "Notable"
        case .building: "Building"
        case .noData, .unknown: "—"
        }
    }

    /// Green is a claim. It is reserved for the one state that earns it.
    var tint: Color {
        switch state {
        case .typical: Theme.Metric.recoveryHigh
        case .watch, .notable: Theme.Metric.recoveryMid
        case .building, .noData, .unknown: Theme.neutral(0.35)
        }
    }

    var symbol: String {
        switch state {
        case .typical: "checkmark.circle.fill"
        case .watch, .notable: "dot.radiowaves.left.and.right"
        case .building: "hourglass"
        case .noData, .unknown: "questionmark.circle"
        }
    }

    /// True only when Zoon can stand behind "nothing unusual".
    var isReassurance: Bool { state == .typical }
}

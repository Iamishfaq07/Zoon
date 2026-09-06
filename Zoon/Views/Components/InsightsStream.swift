import SwiftUI

/// "What changed": this week against last, as a horizontal story stream of
/// three cells, each with a tiny visual signature -- a two-bar comparison
/// for the value, drawn in the metric's family colour -- instead of a card
/// of label/value rows.
///
/// The comparisons are the ones `WhatChangedCard` computed (time asleep,
/// HRV, bedtime steadiness, debt); the arithmetic is lifted verbatim so the
/// two can never disagree. Needs 14 nights; below that renders nothing.
struct WhatChangedStream: View {
    let nights: [SleepNightFeatures]
    let goalMinutes: Double

    struct Change: Identifiable {
        let id: String
        let title: String
        let sentence: String
        let technical: String
        let before: Double
        let after: Double
        let tint: Color
        let isImprovement: Bool?
    }

    private var currentWeek: [SleepNightFeatures] { Array(nights.suffix(7)) }
    private var previousWeek: [SleepNightFeatures] { Array(nights.dropLast(7).suffix(7)) }

    var changes: [Change] {
        // One engine, shared with `WhatChangedCard`. These four comparisons
        // used to be computed here and there independently -- "lifted
        // verbatim" is not the same as shared, and the two had already
        // drifted to different "no change" tests.
        WeekOverWeek.compare(nights: nights, goalMinutes: goalMinutes)
            .prefix(3)
            .map { change in
                Change(
                    id: change.id,
                    title: change.title,
                    sentence: sentence(for: change),
                    technical: technical(for: change),
                    // Bedtime steadiness is drawn as "taller = steadier", so
                    // the bars take the spread inverted while the sentence
                    // above takes the real numbers.
                    before: change.id == "bedtime" ? max(0, 120 - change.before) : change.before,
                    after: change.id == "bedtime" ? max(0, 120 - change.after) : change.after,
                    tint: tint(for: change.id),
                    isImprovement: change.isImprovement
                )
            }
    }

    /// What the cell says.
    ///
    /// A move that did not clear the bars is reported as steady rather than
    /// as a signed number in a neutral colour -- "Up 3 ms from last week" in
    /// grey still reads as something that happened, and the point is that it
    /// has not been shown to have.
    private func sentence(for change: WeekOverWeek.Change) -> String {
        guard change.isMeaningful else {
            switch change.id {
            case "bedtime": return "As consistent as last week"
            case "debt": return "About where it was last week"
            default: return "About the same as last week"
            }
        }
        switch change.id {
        case "hrv":
            return "\(change.delta > 0 ? "Up" : "Down") \(Int(abs(change.delta).rounded())) ms from last week"
        case "bedtime":
            let word = change.delta < 0 ? "more consistent" : "more scattered"
            return "\(Int(abs(change.delta).rounded()))m \(word) than last week"
        case "debt":
            return "\(change.delta < 0 ? "Down" : "Up") \(Self.minutes(abs(change.delta))) from last week"
        default:
            return "\(Self.minutes(abs(change.delta))) \(change.delta > 0 ? "more" : "less") per night than last week"
        }
    }

    /// The numbers behind the sentence, shown whether or not the move cleared
    /// the bars -- the readings are real either way, and seeing them is how
    /// someone checks that "about the same" was fair.
    private func technical(for change: WeekOverWeek.Change) -> String {
        switch change.id {
        case "hrv":
            return "\(Int(change.after.rounded())) vs \(Int(change.before.rounded())) ms average"
        case "bedtime":
            return "±\(Int(change.after.rounded()))m vs ±\(Int(change.before.rounded()))m spread"
        case "debt":
            return "\(Self.minutes(change.after)) owed now, \(Self.minutes(change.before)) a week ago"
        default:
            return "\(Self.minutes(change.after)) vs \(Self.minutes(change.before)) average"
        }
    }

    private func tint(for id: String) -> Color {
        switch id {
        case "hrv": Theme.Family.bodySignals
        case "bedtime": Theme.Family.circadian
        case "debt": Theme.Family.attention
        default: Theme.Family.sleep
        }
    }

    var body: some View {
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ZoonSectionHeader("What changed") {
                    Text("This week vs last")
                        .font(Theme.text(11))
                        .foregroundStyle(.tertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(changes) { change in
                            ChangeCell(change: change)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private static func minutes(_ value: Double) -> String {
        SleepNightFeatures.formatMinutes(value)
    }


}

/// One cell of the stream: title, two-bar before/after signature, sentence,
/// and the technical line beneath in the evidence style.
private struct ChangeCell: View {
    let change: WhatChangedStream.Change
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(change.title)
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            bars

            Text(change.sentence)
                .font(Theme.label(14, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Text(change.technical)
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(width: 200, alignment: .leading)
        .drawOnce(id: change.id + change.technical, progress: $progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(change.title). \(change.sentence). \(change.technical)")
    }

    private var bars: some View {
        let peak = max(change.before, change.after, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            bar(fraction: change.before / peak, tint: change.tint.opacity(0.35), label: "Last week")
            bar(fraction: change.after / peak, tint: change.tint, label: "This week")
            Spacer(minLength: 0)
            if let isImprovement = change.isImprovement {
                Image(systemName: isImprovement ? "arrow.up.right" : "arrow.down.right")
                    .font(Theme.text(11, weight: .bold))
                    .foregroundStyle(isImprovement ? Theme.Family.recovery : Theme.Family.attention)
                    .padding(.bottom, 2)
            }
        }
        .frame(height: 36)
    }

    private func bar(fraction: Double, tint: Color, label: String) -> some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint)
                .frame(width: 22, height: max(4, 30 * fraction * progress))
        }
        .frame(height: 36, alignment: .bottom)
    }
}

#Preview("What changed stream") {
    ScrollView {
        WhatChangedStream(nights: MockData.history, goalMinutes: 480)
            .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}

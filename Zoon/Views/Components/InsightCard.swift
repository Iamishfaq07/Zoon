import SwiftUI

/// Renders a `SleepInsight`.
///
/// Three tiers, because the honest presentation of a guess differs from the
/// honest presentation of a measurement:
///
/// - **summary** — always shown. Factual.
/// - **likelyCause** — shown only when the engine actually identified one, and
///   suppressed at low confidence. Visually distinct so it doesn't read as
///   measured fact.
/// - **actionableTip** — always shown.
struct InsightCard: View {

    let insight: SleepInsight
    var engineName: String?
    /// When set, the card offers a way to ask a follow-up about tonight's
    /// numbers instead of just reading a fixed three-line summary.
    var night: SleepNightFeatures?

    var body: some View {
        // Deliberately not a `.glassCard()` -- the redesign spec singles this
        // card out for an editorial layout, distinct from the boxed, bordered
        // template every other card on the app uses. Headline, evidence, and
        // action are three separated typographic blocks rather than a
        // headline sitting on top of icon+text rows -- the same shape
        // `CoachChatView`'s assistant answers use for the same reason (see
        // its doc comment: "should not look like generic ... bubbles").
        VStack(alignment: .leading, spacing: 14) {
            kicker

            Text(insight.summary)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let cause = insight.likelyCause, insight.confidence > .low {
                Text(cause)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.neutral(0.14)).frame(width: 2)
                    }
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.Metric.sleep)
                Text(insight.actionableTip)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let night {
                NavigationLink {
                    CoachChatView(night: night)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Ask a follow-up")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Theme.text(11, weight: .semibold))
                    }
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var kicker: some View {
        HStack(spacing: 6) {
            Text("TONIGHT'S READ")
                .font(Theme.label(11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            if let engineName {
                Text(engineName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview("With cause") {
    ScrollView {
        InsightCard(insight: MockData.poorInsight, engineName: "Rules")
            .padding()
    }
    .nightBackground()
}

#Preview("No cause") {
    ScrollView {
        InsightCard(insight: MockData.goodInsight, engineName: "Rules")
            .padding()
    }
    .nightBackground()
}

#Preview("Live rule engine") {
    // Runs the real engine so a rule change shows up in previews immediately.
    let engine = RuleBasedInsightEngine()
    let baseline = RollingBaseline(
        hrv7DayAvg: 60, sleepDebtMinutes: 340, deep7DayAvg: 74,
        duration7DayAvg: 420, efficiency7DayAvg: 88, minHeartRate7DayAvg: 53,
        restingHeartRate7DayAvg: 57,
        wristTempBaselineC: 35.1, bedtimeConsistencyMinutes: 72, sampleCount: 7
    )
    return ScrollView {
        VStack(spacing: 16) {
            InsightCard(
                insight: engine.generate(for: MockData.poorNight, baseline: baseline, goalMinutes: 480),
                engineName: "Rules"
            )
            InsightCard(
                insight: engine.generate(for: MockData.goodNight, baseline: baseline, goalMinutes: 480),
                engineName: "Rules"
            )
        }
        .padding()
    }
    .nightBackground()
}

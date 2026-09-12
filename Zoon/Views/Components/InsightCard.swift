import SwiftUI

/// Renders a `SleepInsight`.
///
/// Four blocks, because the honest presentation of a guess differs from the
/// honest presentation of a measurement, and a fact about people in general
/// differs from both:
///
/// - **summary** — always shown. Factual.
/// - **likelyCause** — what was measured about *this* night. Shown only when
///   the engine identified something, and suppressed at low confidence.
/// - **generalContext** — what is known about that pattern across people.
///   Labelled and set apart, because the whole point of the field existing is
///   that it must not read in the same voice as the line above it. A person
///   who cannot tell which of the two is about them is being misled by
///   layout, whatever the words say.
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

            if insight.confidence > .low {
                if let cause = insight.likelyCause {
                    Text(cause)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.neutral(0.14)).frame(width: 2)
                        }
                }

                if let context = insight.generalContext {
                    generalBlock(context)
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

    /// The general-population tier.
    ///
    /// Deliberately quieter than the measurement above it and carrying its own
    /// label -- no rail, smaller type, tertiary colour. Without the label a
    /// reader has no way to tell that this sentence is about people in general
    /// and the one above is about them, which is the failure the two fields
    /// exist to prevent. Doing the separation in the model and then rendering
    /// both as one grey paragraph would have changed nothing.
    private func generalBlock(_ context: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("IN GENERAL, NOT MEASURED IN YOU")
                .font(Theme.label(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.inkTertiary)
            Text(context)
                .font(Theme.text(13))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 10)
        .accessibilityElement(children: .combine)
    }

    private var kicker: some View {
        HStack(spacing: 6) {
            Text("TONIGHT'S READ")
                .font(Theme.label(11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            if let engineName {
                Text(engineName)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkTertiary)
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

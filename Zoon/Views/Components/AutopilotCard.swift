import SwiftUI

/// Tonight's bed and wake target from `SleepAutopilot`.
///
/// Sits directly under `TonightTimelineCard`, which draws the schedule the
/// person already keeps. This one says whether to move it, and by how much.
/// The two read as a pair on purpose: the timeline is where tonight is
/// heading, this is the one adjustment worth making to it.
///
/// The card renders the holding case as prominently as the moving case. An
/// autopilot that only appears when it wants something changed teaches
/// people that opening it means being told off; showing "tonight looks like
/// your usual night" is the same engine reporting the same confidence, and
/// suppressing it would quietly bias what the feature appears to be for.
struct AutopilotCard: View {

    let plan: SleepAutopilot.Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: plan.isHolding ? "checkmark.circle.fill" : "arrow.left.arrow.right.circle.fill")
                    .font(Theme.text(14, weight: .semibold))
                    .foregroundStyle(plan.isHolding ? Theme.Metric.recoveryHigh : Theme.Metric.sleep)
                Text("Tonight's target")
                    .font(Theme.label(13, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(plan.confidence.label)
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(clock(plan.targetBedtimeMinutes))
                    .font(Theme.label(28, weight: .semibold))
                    .monospacedDigit()
                Image(systemName: "arrow.right")
                    .font(Theme.text(12))
                    .foregroundStyle(.tertiary)
                Text(clock(plan.targetWakeMinutes))
                    .font(Theme.label(28, weight: .semibold))
                    .monospacedDigit()
            }

            Text(plan.sentence)
                .font(Theme.text(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(plan.caveat)
                .font(Theme.text(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Delegates to the engine so the phone, watch and widget all fold the
    /// clock the same way -- see `SleepAutopilot.clockLabel`.
    private func clock(_ minutes: Double) -> String {
        SleepAutopilot.clockLabel(minutes)
    }
}

/// Both states, because the argument for this card is that the holding case
/// has to read as an answer rather than as an absence. If "no change worth
/// making" looks like an empty card next to the shifting one, that argument
/// has lost, and this is the pair that shows it.
///
/// The plans are built directly rather than run through `SleepAutopilot.plan`:
/// coaxing the engine into holding needs a history whose median happens to sit
/// inside the deadband, which is a fixture to maintain rather than a thing to
/// look at.
#Preview("Autopilot - shifting") {
    AutopilotCard(plan: SleepAutopilot.Plan(
        targetBedtimeMinutes: -20,
        targetSleepMinutes: 480,
        shiftMinutes: -20,
        debtRepaymentMinutes: 30,
        isHolding: false,
        confidence: .moderate
    ))
    .padding()
    .zoonPreviewEnvironment()
}

#Preview("Autopilot - holding") {
    AutopilotCard(plan: SleepAutopilot.Plan(
        targetBedtimeMinutes: -52,
        targetSleepMinutes: 465,
        shiftMinutes: 0,
        debtRepaymentMinutes: 0,
        isHolding: true,
        confidence: .high
    ))
    .padding()
    .zoonPreviewEnvironment()
}

/// The two-time headline is a `firstTextBaseline` HStack of two scaled
/// numerals with an arrow between them -- the row most likely to wrap badly.
#Preview("Autopilot - large text") {
    AutopilotCard(plan: SleepAutopilot.Plan(
        targetBedtimeMinutes: -20,
        targetSleepMinutes: 480,
        shiftMinutes: -20,
        debtRepaymentMinutes: 30,
        isHolding: false,
        confidence: .moderate
    ))
    .padding()
    .zoonPreviewEnvironment()
    .environment(\.dynamicTypeSize, .accessibility3)
}

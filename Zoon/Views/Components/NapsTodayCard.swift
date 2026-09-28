import SwiftUI

/// Naps taken today, and what they do to tonight's plan.
///
/// **The gap this closes.** Nap credit is attributed to the calendar day
/// *before* a night's wake — `SleepContextWindow.napDay(before:)` returns
/// `[startOfDay(wake) − 1 day, startOfDay(wake))`. That is the right window
/// for a finished night: it is the 24 hours leading up to that wake. But it
/// means a nap taken this afternoon falls in the window belonging to
/// *tomorrow morning's* record, so it stays invisible until tomorrow's night
/// is recorded. Sleep at two o'clock and the app still showed the same
/// shortfall at six.
///
/// So today's naps are read live, from `NapStore`, on the day they happen.
/// This is a running total for today rather than a correction to last
/// night's record: last night is finished and its figures do not move. What
/// moves is what today's shortfall still is, which is the number a nap was
/// meant to change.
struct NapsTodayCard: View {

    let napMinutesToday: Double
    /// What today's naps take off tonight's target
    /// (`SleepPlanningInputs.tonightNapEffectMinutes`).
    let targetReductionMinutes: Double
    let recommendation: NapCoach.Recommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZoonSectionHeader("Naps today")

            if napMinutesToday > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(SleepNightFeatures.formatMinutes(napMinutesToday))
                        .font(Theme.numeral(26))
                        .foregroundStyle(Theme.Family.sleep)
                    Text("napped")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Text(effectLine)
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No nap yet today.")
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Divider().overlay(Theme.neutral(0.12))

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: adviceSymbol)
                    .font(Theme.text(14, weight: .semibold))
                    .foregroundStyle(adviceTint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(adviceTitle)
                        .font(Theme.label(13, weight: .semibold))
                        .foregroundStyle(adviceTint)
                    Text(recommendation.reason)
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if recommendation.isRecommended {
                NavigationLink {
                    NapView()
                } label: {
                    Label("Start a nap", systemImage: "powersleep")
                        .font(Theme.label(14, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Family.sleep)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Says what the nap did. Not "that takes X off today's shortfall": the
    /// shortfall only records nights below target, so the figure the card
    /// promised came back the next morning even when tonight's (lowered)
    /// target was met. What a nap changes is tonight's target.
    private var effectLine: String {
        guard targetReductionMinutes >= 1 else {
            return "Tonight's target is already as low as Zoon sets it, so this nap doesn't lower it further."
        }
        return "That lowers tonight's target by \(SleepNightFeatures.formatMinutes(targetReductionMinutes))."
    }

    private var adviceTitle: String {
        switch recommendation.advice {
        case .recommended(let minutes): "A \(minutes)-minute nap would help"
        case .optional: "A nap is optional"
        case .avoid: "Better not to nap now"
        }
    }

    private var adviceSymbol: String {
        switch recommendation.advice {
        case .recommended: "checkmark.circle.fill"
        case .optional: "circle.dashed"
        case .avoid: "exclamationmark.triangle.fill"
        }
    }

    private var adviceTint: Color {
        switch recommendation.advice {
        case .recommended: Theme.Family.recovery
        case .optional: Theme.Family.sleep
        case .avoid: Theme.Family.attention
        }
    }
}

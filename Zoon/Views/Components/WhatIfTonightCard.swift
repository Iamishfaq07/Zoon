import SwiftUI

/// Move tonight's window and watch what follows from it.
///
/// Everything this shows is arithmetic on a clock: push bedtime an hour later
/// against a fixed alarm and the window loses an hour. That is subtraction,
/// not a model, and it is true before the night happens — which is exactly
/// why it can be shown while there is still time to act on it.
///
/// It says nothing about Recovery, a Sleep Score, or how anyone will feel.
/// Those would need a validated model of a night that has not happened.
///
/// Adjusted with steppers rather than a custom drag surface. A drag is the
/// more obvious reading of "drag the bedtime", but a fifteen-minute step is
/// the granularity the answer is good to anyway, it is operable with
/// VoiceOver and Switch Control without a bespoke accessibility adaptor, and
/// it cannot be nudged by a scroll.
struct WhatIfTonightCard: View {

    let plan: ZoonTomorrow.Plan
    /// Baseline need, the outstanding shortfall and tonight's own modifiers.
    /// Composed here rather than upstream so the repayment is applied once —
    /// see `SleepPlanningInputs`.
    let planning: SleepPlanningInputs
    var napMinutesToday: Double = 0

    @State private var bedtime: Date?
    @State private var wake: Date?

    /// Minutes per tap. Fifteen is about the resolution the underlying need
    /// is good to, so a finer step would imply a precision the comparison
    /// does not have.
    private static let step = 15

    private var model: WhatIfTonight {
        WhatIfTonight(
            bedtime: bedtime ?? plan.bedtime,
            wake: wake ?? plan.wake,
            needMinutes: planning.tonightNeedMinutes,
            shortfallMinutes: planning.currentShortfallMinutes,
            baseNeedMinutes: planning.tonightNeedBeforeRepaymentMinutes,
            reference: WhatIfTonight.Reference(bedtime: plan.bedtime, wake: plan.wake)
        )
    }

    private var hasMoved: Bool {
        (bedtime != nil && bedtime != plan.bedtime) || (wake != nil && wake != plan.wake)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "What if tonight",
                subtitle: "Move the window and see what follows. Nothing here predicts how you will sleep.",
                systemImage: "slider.horizontal.below.rectangle"
            )

            adjuster(
                title: "Bed at",
                date: model.bedtime,
                set: { bedtime = $0 },
                current: bedtime ?? plan.bedtime
            )
            adjuster(
                title: "Wake at",
                date: model.wake,
                set: { wake = $0 },
                current: wake ?? plan.wake
            )

            Text(model.sentence())
                .font(Theme.text(14, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.rows(), id: \.label) { row in
                    // Label and value stack rather than sit side by side at
                    // accessibility sizes: these values are clock times and
                    // durations, and pinning them opposite a label is where
                    // they start wrapping mid-word.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            rowLabel(row.label)
                            Spacer(minLength: 6)
                            rowValue(row.value, isShort: row.value.hasPrefix("−"))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            rowLabel(row.label)
                            rowValue(row.value, isShort: row.value.hasPrefix("−"))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.label), \(row.value)")
                }
            }

            if hasMoved {
                Button("Back to tonight's plan") {
                    bedtime = nil
                    wake = nil
                    Haptics.tap()
                }
                .buttonStyle(.bordered)
            }

            Text("Sleep opportunity is the most this window leaves room for, not how much you will sleep.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.label(12))
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rowValue(_ text: String, isShort: Bool) -> some View {
        Text(text)
            .font(Theme.numeral(14))
            .monospacedDigit()
            // Never colour alone: a short window carries a signed value, so
            // the minus sign is the signal and the tint only reinforces it.
            .foregroundStyle(isShort ? Theme.Metric.strain : Theme.ink)
    }

    private func adjuster(
        title: String,
        date: Date,
        set: @escaping (Date) -> Void,
        current: Date
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Theme.label(12))
                .foregroundStyle(Theme.inkSecondary)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(Theme.numeral(18))
                .monospacedDigit()
            Spacer(minLength: 6)
            Stepper(title) {
                set(current.addingTimeInterval(Double(Self.step) * 60))
                Haptics.select()
            } onDecrement: {
                set(current.addingTimeInterval(Double(-Self.step) * 60))
                Haptics.select()
            }
            .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(date.formatted(date: .omitted, time: .shortened))")
        .accessibilityHint("Adjusts in \(Self.step)-minute steps.")
    }
}

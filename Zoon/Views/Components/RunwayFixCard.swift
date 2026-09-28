import SwiftUI

/// The smallest bedtime changes that make room for a short morning.
///
/// `SleepRunwayOptimizer` shipped with tests and no screen: the runway could
/// say "Friday is 55 minutes short" and stop there, leaving the arithmetic to
/// the person. This is the rest of that sentence — which nights to go to bed
/// earlier, by how much, and which wake time to leave alone.
struct RunwayFixCard: View {
    let plan: SleepRunwayOptimizer.Plan
    /// Renders a time on this device's clock.
    var clock: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "How to make room",
                subtitle: "The smallest bedtime changes that fit the week.",
                systemImage: "wand.and.stars"
            )

            Text(plan.sentence)
                .font(Theme.text(15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { offset, step in
                    stepRow(step)
                        .opacity(shown ? 1 : 0)
                        .offset(x: shown ? 0 : 16)
                        .animation(
                            Motion.respecting(reduceMotion, Motion.entrance.delay(Double(offset) * 0.08)),
                            value: shown
                        )
                }
            }

            if plan.closesTheGap {
                Label("That closes the gap.", systemImage: "checkmark.circle.fill")
                    .font(Theme.label(14, weight: .semibold))
                    .foregroundStyle(Theme.Family.recovery)
            } else {
                Label(
                    "Still about \(Int(plan.residualGapMinutes.rounded())) minutes short. A short nap that day, or moving the morning, would cover the rest.",
                    systemImage: "exclamationmark.circle"
                )
                .font(Theme.text(14))
                .foregroundStyle(Theme.Family.attention)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(plan.caveat)
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
        .onAppear { shown = true }
    }

    @ViewBuilder
    private func stepRow(_ step: SleepRunwayOptimizer.Step) -> some View {
        switch step {
        case let .shiftBedtime(date, minutes, from):
            let newBedtime = from.addingTimeInterval(-minutes * 60)
            row(
                symbol: "moon.zzz.fill",
                tint: Theme.Metric.sleep,
                day: date.formatted(.dateTime.weekday(.wide)),
                text: "Bed at \(clock(newBedtime)), \(Int(minutes)) min earlier than usual"
            )
        case let .protectWakeTime(date, wake, source):
            row(
                symbol: "alarm.fill",
                tint: Theme.Metric.battery,
                day: date.formatted(.dateTime.weekday(.wide)),
                text: "Keep the \(clock(wake)) wake. \(source.label)."
            )
        }
    }

    private func row(symbol: String, tint: Color, day: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(Theme.text(14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(day)
                    .font(Theme.label(14, weight: .semibold))
                Text(text)
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

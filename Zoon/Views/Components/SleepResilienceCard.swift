import SwiftUI

struct SleepResilienceCard: View {
    let nights: [SleepNightFeatures]

    /// Overall bounce-back, against this person's own band rather than a
    /// flat twenty-five minutes.
    ///
    /// That constant was a claim that every sleeper varies by the same
    /// amount. For someone whose nights sit within ten minutes of each other
    /// it made almost nothing a disruption; for someone genuinely erratic it
    /// swallowed real ones. Both failures were silent — the card simply
    /// reported the wrong thing confidently.
    private var bounce: SleepResilience.Result {
        let points = nights.map {
            SleepResilience.Observation(date: $0.date, value: $0.timeAsleepMinutes)
        }
        let values = points.map(\.value)
        guard let baseline = Statistics.median(values),
              let tolerance = SleepResilience.personalTolerance(
                values,
                floor: SleepResilience.durationToleranceFloor,
                ceiling: SleepResilience.durationToleranceCeiling
              )
        else {
            return SleepResilience.Result(
                state: .insufficientHistory(
                    nights: points.count, required: SleepResilience.minimumNights
                ),
                eventCount: 0,
                censoredCount: 0,
                nightCount: points.count
            )
        }
        return SleepResilience.measure(
            observations: points,
            baseline: baseline,
            tolerance: tolerance,
            direction: .belowIsDisruption
        )
    }

    /// Bounce-back split by what knocked the sleep off course.
    ///
    /// Only the kinds that have actually produced a measured answer. A row
    /// reading "not enough history yet" for every type is a list of ways
    /// Zoon cannot help, and the card already says that once above.
    private var byType: [SleepResilience.TypedResult] {
        SleepResilience.byDisruptionType(nights: nights)
            .filter { $0.result.state.medianNights != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sleep resilience", systemImage: "arrow.uturn.backward")
            Text(sentence)
                .font(Theme.text(22, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Disruption")
                    .font(Theme.label(11, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                Circle().fill(Theme.Metric.strain).frame(width: 8, height: 8)
                Capsule().fill(Theme.neutral(0.16)).frame(height: 2)
                Circle().fill(Theme.neutral(0.3)).frame(width: 8, height: 8)
                Capsule().fill(Theme.neutral(0.16)).frame(height: 2)
                Circle().fill(Theme.Metric.recoveryHigh).frame(width: 8, height: 8)
                Text("Baseline")
                    .font(Theme.label(11, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            if !byType.isEmpty {
                Divider().overlay(Theme.cardStroke)
                VStack(alignment: .leading, spacing: 6) {
                    Text("By what disrupted it")
                        .font(Theme.label(11, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    ForEach(byType) { typed in
                        // Label and value stack rather than sit side by side
                        // at accessibility sizes: "usual bounce-back: 2.6
                        // nights" is already a long value and pinning it
                        // beside a label is where it starts wrapping into
                        // one word per line.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                typeLabel(typed)
                                Spacer(minLength: 6)
                                typeValue(typed)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                typeLabel(typed)
                                typeValue(typed)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(typed.kind.label), \(typed.sentence). \(typed.result.eventCount) episodes.")
                    }
                }
            }

            Text("Measured against your own nights and your own variability. Not an age, not a diagnosis.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sentence)
    }

    private func typeLabel(_ typed: SleepResilience.TypedResult) -> some View {
        Text(typed.kind.label)
            .font(Theme.label(12, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The episode count travels with the number, always. A bounce-back
    /// measured across three disruptions and one measured across twenty are
    /// not the same claim, and the number alone does not say which.
    private func typeValue(_ typed: SleepResilience.TypedResult) -> some View {
        Text("\(typed.sentence) · \(typed.result.eventCount) episodes")
            .font(Theme.text(11))
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sentence: String {
        switch bounce.state {
        case .insufficientHistory(let nights, let required):
            return "Zoon is learning your bounce-back. \(nights) of \(required) nights collected."
        case .steady:
            return "Recent nights have stayed inside your usual length. Nothing to recover from."
        case .tooFewEvents(let found, let required):
            return "Only \(found) disruption\(found == 1 ? "" : "s") so far. Zoon needs \(required) before this is a pattern."
        case .measured(let median):
            let nights = Int(median.rounded())
            return "You typically return to your usual sleep length within \(nights) night\(nights == 1 ? "" : "s") after a short night."
        }
    }
}

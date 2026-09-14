import SwiftUI

struct SleepResilienceCard: View {
    let nights: [SleepNightFeatures]

    private var bounce: SleepResilience.Result {
        let points = nights.compactMap { night -> SleepResilience.Observation? in
            SleepResilience.Observation(date: night.date, value: night.timeAsleepMinutes)
        }
        let baseline = Statistics.median(points.map(\.value)) ?? 0
        return SleepResilience.measure(
            observations: points,
            baseline: baseline,
            tolerance: 25,
            direction: .belowIsDisruption
        )
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
            Text("Measured against your own nights. Not an age, not a diagnosis.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sentence)
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

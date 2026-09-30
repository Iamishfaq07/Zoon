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
            // A number and a path, not a 22-point sentence. When there is a
            // measurement, the path has one step per night it takes to get
            // back, so "1 night" and "3 nights" look different before either
            // is read.
            if case .measured(let median) = bounce.state {
                let nights = max(1, Int(median.rounded()))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(nights)")
                        .font(Theme.numeral(44))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Metric.recoveryHigh)
                    Text(nights == 1 ? "night to bounce back\nafter a short night" : "nights to bounce back\nafter a short night")
                        .font(Theme.text(14, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BouncePath(steps: nights)
            } else {
                Text(sentence)
                    .font(Theme.text(17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !byType.isEmpty {
                Divider().overlay(Theme.cardStroke)
                VStack(alignment: .leading, spacing: 6) {
                    Text("By what disrupted it")
                        .font(Theme.label(11, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    let longest = max(1, byType.compactMap { $0.result.state.medianNights }.max() ?? 1)
                    ForEach(byType) { typed in
                        let value = typed.result.state.medianNights ?? 0
                        HStack(spacing: 8) {
                            Text(typed.kind.label)
                                .font(Theme.label(12, weight: .medium))
                                .frame(width: 96, alignment: .leading)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.neutral(0.08))
                                    Capsule()
                                        .fill(Theme.Metric.strain.opacity(0.8))
                                        .frame(width: max(6, proxy.size.width * value / longest))
                                }
                            }
                            .frame(height: 8)
                            Text(String(format: value < 10 ? "%.1f" : "%.0f", value))
                                .font(Theme.text(11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(minWidth: 28, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(typed.kind.label), \(typed.sentence). \(typed.result.eventCount) episodes.")
                    }
                    Text("Nights to bounce back, by cause")
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }

            Text("Against your own nights. Not a diagnosis.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
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

/// Short night, then one step per night of recovery, ending at your usual
/// length. The steps fill in turn when the card appears.
private struct BouncePath: View {
    let steps: Int

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let count = min(steps, 6)
        HStack(spacing: 6) {
            VStack(spacing: 3) {
                Circle().fill(Theme.Metric.strain).frame(width: 12, height: 12)
                Text("Short").font(Theme.text(10)).foregroundStyle(Theme.inkTertiary)
            }
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index < shown ? Theme.Metric.recoveryHigh.opacity(0.35 + 0.6 * Double(index + 1) / Double(count)) : Theme.neutral(0.12))
                    .frame(height: 4)
                    .padding(.bottom, 14)
            }
            VStack(spacing: 3) {
                Circle().fill(shown >= count ? Theme.Metric.recoveryHigh : Theme.neutral(0.25)).frame(width: 12, height: 12)
                Text("Usual").font(Theme.text(10)).foregroundStyle(Theme.inkTertiary)
            }
        }
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else { shown = count; return }
            for step in 1...max(1, count) {
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.easeOut(duration: 0.25)) { shown = step }
            }
        }
    }
}

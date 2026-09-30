import SwiftUI

/// "What's usually present before my best sleep" -- see `SleepPlaybook`'s
/// own doc comment for how this differs from Cause Finder.
struct SleepPlaybookView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    private var playbook: SleepPlaybook? {
        // Nights with no known sleep sufficiency are excluded entirely,
        // rather than defaulting the outcome to 0 -- a data gap is not
        // evidence of a bad night, and letting it stand in as one would
        // corrupt the best-quarter ranking with nights that never happened.
        let known = coordinator.journalObservations().enumerated().compactMap { _, observation in
            observation.sleepPerformance.map { (observation: observation, outcome: $0) }
        }
        let outcomes = known.map(\.outcome)
        let inputs = BehaviorTag.allCases.map { tag in
            SleepPlaybook.FactorInput(
                id: tag.rawValue,
                label: tag.label,
                presencePerNight: known.map { entry in
                    switch entry.observation.exposureState(for: tag) {
                    case .yes: true
                    case .no: false
                    case .unknown: nil
                    }
                }
            )
        }
        return SleepPlaybook.build(outcomePerNight: outcomes, factorInputs: inputs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                header
                if let playbook, !playbook.factors.isEmpty {
                    ForEach(Array(playbook.factors.enumerated()), id: \.element.id) { index, factor in
                        FactorRow(factor: factor)
                            .entrance(index)
                    }
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Sleep Playbook")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's usually there on your best nights")
                .font(Theme.heading(18))
            Text("From your own nights. Patterns, not proof.")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var emptyState: some View {
        Text("Nothing yet. Needs at least \(SleepPlaybook.minimumNights) journaled nights.")
            .font(.caption)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
    }
}

private struct FactorRow: View {
    let factor: SleepPlaybook.Factor

    private var tag: BehaviorTag? { BehaviorTag(rawValue: factor.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let tag {
                    Image(systemName: tag.symbol)
                        .foregroundStyle(Theme.Metric.recoveryHigh)
                        .frame(width: 24, height: 24)
                        .background(Theme.Metric.recoveryHigh.opacity(0.15), in: Circle())
                }
                Text(factor.label)
                    .font(Theme.label(14, weight: .semibold))
                Spacer()
            }

            // Two bars instead of a sentence of percentages: how often this
            // was there on your best nights, against the rest.
            rateBar("Best nights", rate: factor.bestNightsRate, tint: Theme.Metric.recoveryHigh)
            rateBar("Other nights", rate: factor.otherNightsRate, tint: Theme.neutral(0.35))
            Text("\(factor.sampleSize) best nights · \(factor.confidence.label)")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
        }
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(factor.label). Present on \(Int((factor.bestNightsRate * 100).rounded()))% of your best nights, vs \(Int((factor.otherNightsRate * 100).rounded()))% on the rest. \(factor.sampleSize) best nights, \(factor.confidence.label.lowercased()).")
    }

    private func rateBar(_ title: String, rate: Double, tint: Color) -> some View {
        LabeledBar(
            title: title,
            valueText: "\(Int((rate * 100).rounded()))%",
            fraction: rate,
            tint: tint,
            labelWidth: 78
        )
    }

}

#Preview("Sleep Playbook") {
    NavigationStack { SleepPlaybookView() }
        .zoonPreviewEnvironment()
}

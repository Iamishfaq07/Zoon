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
                    ForEach(playbook.factors) { factor in
                        FactorRow(factor: factor)
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
                .font(Theme.numeral(18))
            Text("Built from your own history -- conditions that show up disproportionately around your best sleep, not a hypothesis test on any one behaviour.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        Text("""
            Nothing clears the bar yet. Zoon needs at least \(SleepPlaybook.minimumNights) journaled nights, \
            and a condition needs a real enough gap between your best nights and the rest before it shows up here.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
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

            Text("Present on \(Int((factor.bestNightsRate * 100).rounded()))% of your best nights, vs \(Int((factor.otherNightsRate * 100).rounded()))% on the rest -- \(factor.sampleSize) best nights with a known answer, \(factor.confidence.label.lowercased()).")
                .font(Theme.text(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

#Preview("Sleep Playbook") {
    NavigationStack { SleepPlaybookView() }
        .zoonPreviewEnvironment()
}

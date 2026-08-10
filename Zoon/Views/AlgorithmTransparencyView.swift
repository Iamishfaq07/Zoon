import SwiftUI

/// "How your score works" — the actual weight table, read directly from
/// `SleepIntelligenceScore`, not a hand-copied duplicate that could drift out
/// of sync with the real algorithm.
struct AlgorithmTransparencyView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                header
                weightsCard
                reweightingCard
                versionCard
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Sleep Intelligence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How your score works")
                .font(Theme.numeral(20))
            Text("Seven components, each measured against your own recent history rather than a fixed target or another user's data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var weightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Components", systemImage: "chart.bar.doc.horizontal")
            ForEach(SleepIntelligenceScore.nominalWeights, id: \.component) { entry in
                HStack {
                    Text(entry.component)
                        .font(Theme.label(13, weight: .medium))
                    Spacer()
                    Text("\(Int(entry.weight * 100))%")
                        .font(Theme.label(13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Metric.sleep)
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.Metric.sleep.opacity(0.6))
                        .frame(width: geo.size.width * entry.weight)
                }
                .frame(height: 5)
            }
        }
        .glassCard()
    }

    private var reweightingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Missing data doesn't count against you", systemImage: "checkmark.shield")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("""
                Components with missing data -- no HRV sensor, not enough history for a body \
                clock yet, a source without stage detail -- are excluded, and the remaining \
                components' weights scale up to fill 100%. A night is never scored as if a \
                missing input were zero.
                """)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var versionCard: some View {
        HStack {
            Text("Algorithm")
                .font(Theme.label(12))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Sleep Intelligence v\(SleepIntelligenceScore.currentVersion).0")
                .font(Theme.label(12, weight: .semibold))
        }
        .glassCard()
    }
}

#Preview("Algorithm Transparency") {
    NavigationStack { AlgorithmTransparencyView() }
        .preferredColorScheme(.dark)
}

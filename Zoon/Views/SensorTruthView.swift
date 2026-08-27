import SwiftUI

/// Every number the app shows, and what kind of claim each one is.
///
/// Reached from the Evidence screen rather than from Settings, because it
/// answers the same question that screen exists for -- how much of this
/// should I believe -- one level further down. Evidence grades the *claims*
/// Zoon makes; this grades the *numbers* those claims are built from.
///
/// Ordered softest first, matching `SensorTruth.all`. A glossary sorted
/// alphabetically would bury the two entries that actually change how
/// someone reads their data: that sleep stages are a model's guess, and that
/// blood oxygen is not a medical measurement.
struct SensorTruthView: View {

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("A wrist temperature is a thing a sensor recorded. A REM minute-count is a model's guess. Both look the same on a card, so here is which is which.")
                    .font(Theme.text(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                    .entrance(0)

                ForEach(Array(SensorTruth.all.enumerated()), id: \.element.id) { index, fact in
                    row(fact).entrance(min(index + 1, 6))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Where the numbers come from")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ fact: SensorTruth.Fact) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(fact.quantity.label)
                    .font(Theme.label(15, weight: .semibold))
                Spacer(minLength: 8)
                Text(fact.provenance.label)
                    .font(Theme.text(11, weight: .semibold))
                    .foregroundStyle(tint(fact.provenance))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint(fact.provenance).opacity(0.15), in: Capsule())
            }

            Text(fact.quantity.whatItIs)
                .font(Theme.text(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // The limit is the reason this screen exists, so it is never
            // collapsed behind a disclosure.
            Text(fact.quantity.limit)
                .font(Theme.text(12))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if fact.isWeakenedByItsInputs, let first = fact.weakenedBy.first {
                Text("Shown as \(fact.provenance.label.lowercased()) because \(first.label.lowercased()) is.")
                    .font(Theme.text(12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Same colour vocabulary as the Evidence screen's tiers: cooling as the
    /// claim weakens, so the two screens teach one scale rather than two.
    private func tint(_ provenance: SensorTruth.Provenance) -> Color {
        switch provenance {
        case .measured: Theme.Metric.recoveryHigh
        case .derived: Theme.Metric.strain
        case .inferred: Theme.Metric.sleep
        case .selfReported: .secondary
        }
    }
}

#Preview("Where the numbers come from") {
    NavigationStack { SensorTruthView() }
        .zoonPreviewEnvironment()
}

/// Every row pairs a title with a provenance capsule on the same line, which
/// is where large text crowds first.
#Preview("Where the numbers come from - large text") {
    NavigationStack { SensorTruthView() }
        .zoonPreviewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

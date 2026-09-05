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

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    /// What the chosen watch has actually written, counted from history.
    ///
    /// `nil` when there are too few nights from that source to tell the
    /// difference between "does not measure this" and "synced yesterday".
    private var coverage: SourceCoverage.Report? {
        SourceCoverage.report(
            nights: coordinator.recentNights,
            sourceName: preferences.preferredSleepSourceName
                ?? coordinator.recentNights.last?.sourceName,
            bundleIdentifier: preferences.preferredSleepSourceBundleIdentifier
        )
    }

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

                if let coverage {
                    watchSection(coverage).entrance(1)
                }

                ForEach(Array(SensorTruth.all.enumerated()), id: \.element.id) { index, fact in
                    row(fact).entrance(min(index + 2, 6))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Where the numbers come from")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - What this watch provides

    /// The second question this screen has to answer.
    ///
    /// `SensorTruth` above says what kind of claim each number is. It says
    /// nothing about whether *your* watch supplies it, and that is what
    /// decides how much of Zoon works for you. A Recovery score assembled
    /// from half its usual inputs looks exactly like one assembled from all
    /// of them, which is the gap this closes.
    ///
    /// Everything here is counted from nights already on the device -- see
    /// `SourceCoverage` for why it is measured rather than looked up in a
    /// per-brand table.
    @ViewBuilder
    private func watchSection(_ report: SourceCoverage.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(Theme.text(13, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
                Text("What \(report.source.possessivePhrase) provides")
                    .font(Theme.label(15, weight: .semibold))
            }

            Text("Counted from your last \(report.nightsConsidered) nights from this source, not from a list of what the model is supposed to do.")
                .font(Theme.text(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if report.providesEverything {
                Text("Everything Zoon reads is arriving.")
                    .font(Theme.text(13))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(report.missingFromSource) { entry in
                missingRow(entry, note: "Zoon works without it and says so where it matters.")
            }

            // Different reason, different sentence -- see
            // `Report.missingBecauseAppleOnly`.
            ForEach(report.missingBecauseAppleOnly) { entry in
                missingRow(entry, note: "Apple Watch only. No third-party watch can write this to Health, so there is no setting to change.")
            }

            if !report.provided.isEmpty {
                Divider().overlay(Theme.neutral(0.12))
                ForEach(report.provided) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.quantity.label)
                            .font(Theme.text(13))
                        Spacer(minLength: 8)
                        Text(entry.availability.label)
                            .font(Theme.text(11, weight: .semibold))
                            .foregroundStyle(
                                entry.availability == .usually
                                    ? Theme.Metric.recoveryHigh : Theme.Metric.strain
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func missingRow(_ entry: SourceCoverage.Entry, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.quantity.label)
                    .font(Theme.text(13, weight: .semibold))
                Spacer(minLength: 8)
                Text(entry.availability.label)
                    .font(Theme.text(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.neutral(0.12), in: Capsule())
            }
            Text(note)
                .font(Theme.text(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

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

    /// Last night, and how each of its numbers was arrived at.
    private var tonight: TonightsData? {
        guard let night = coordinator.recentNights.last else { return nil }
        return TonightsData.build(night: night, coverage: coverage)
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

                if let tonight, !tonight.populated.isEmpty {
                    tonightSection(tonight).entrance(2)
                }

                ForEach(Array(SensorTruth.all.enumerated()), id: \.element.id) { index, fact in
                    row(fact).entrance(min(index + 3, 6))
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

            // "Everything is arriving" is only true of *this* watch when
            // nothing is being supplied by a different one -- see
            // `Report.suppliedElsewhere`.
            if report.providesEverything && report.suppliedElsewhere.isEmpty {
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
                    providedRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// A quantity that is arriving, and who is actually writing it.
    ///
    /// The second line is the point. The physiology queries average over the
    /// night's asleep intervals with no source predicate, so a second device
    /// on the same wrist contributes to the number -- and this card used to
    /// credit all of it to whichever source wrote the sleep samples. It stays
    /// silent when provenance was never recorded rather than guessing.
    private func providedRow(_ entry: SourceCoverage.Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.quantity.label)
                    .font(Theme.text(13))
                Spacer(minLength: 8)
                // The night count, not only a word. "Most nights" is the
                // summary; "26 of 30" is the thing someone can check.
                Text("\(entry.nightsWithValue) of \(entry.nightsConsidered)")
                    .font(Theme.text(11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(
                        entry.availability == .usually
                            ? Theme.Metric.recoveryHigh : Theme.Metric.strain
                    )
            }

            // A bar rather than a coloured dot: the V9 audit asked for
            // coverage to be legible at a glance *and* checkable, and a dot
            // carries one bit while excluding anyone who cannot separate the
            // two colours.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.neutral(0.10))
                    Capsule()
                        .fill(
                            entry.availability == .usually
                                ? Theme.Metric.recoveryHigh : Theme.Metric.strain
                        )
                        .frame(width: max(2, geometry.size.width * entry.fraction))
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
            if let note = entry.attributionNote {
                Text(note)
                    .font(Theme.text(11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Tonight's data

    /// Last night's numbers, each with where it came from.
    ///
    /// The section the V9 audit asked for and the reason this screen stops
    /// being a glossary. Everything above is general -- what kind of claim a
    /// REM figure is, what this watch has provided over a month. This is the
    /// specific case: *this* number, last night, and the steps between the
    /// samples and it.
    ///
    /// Every value here was already stored and none of it was shown. Which
    /// device wrote each measurement has been recorded since per-metric
    /// provenance landed; whether time in bed was measured or reconstructed
    /// has been on `SleepNightFeatures` since V5 and never surfaced anywhere.
    @ViewBuilder
    private func tonightSection(_ data: TonightsData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(Theme.text(13, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
                Text("Last night, and how Zoon got it")
                    .font(Theme.label(15, weight: .semibold))
            }

            ForEach(Array(data.populated.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(Theme.neutral(0.10))
                }
                tonightRow(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func tonightRow(_ row: TonightsData.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.quantity.label)
                    .font(Theme.text(12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(row.provenance.label)
                    .font(Theme.text(10, weight: .semibold))
                    .foregroundStyle(tint(row.provenance))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tint(row.provenance).opacity(0.15), in: Capsule())
            }

            Text(row.value)
                .font(Theme.numeral(24))
                .monospacedDigit()

            if !row.sourceNames.isEmpty {
                Text(SourceCoverage.list(row.sourceNames))
                    .font(Theme.text(11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let note = row.note {
                Text(note)
                    .font(Theme.text(11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !row.derivation.isEmpty {
                DisclosureGroup("How Zoon got this") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(row.derivation.enumerated()), id: \.offset) { step, text in
                            HStack(alignment: .top, spacing: 6) {
                                // The arrow says these are stages of one
                                // pipeline rather than an unordered list of
                                // facts, which is the whole point of showing
                                // them.
                                Text(step == 0 ? "•" : "↓")
                                    .font(Theme.text(10))
                                    .foregroundStyle(.tertiary)
                                Text(text)
                                    .font(Theme.text(11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .font(Theme.text(11, weight: .medium))
                .tint(Theme.Metric.sleep)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

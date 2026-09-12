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

    /// How often the range Zoon draws has actually contained the night.
    ///
    /// State rather than a computed property, and filled in a task, because
    /// `backtestAll` rebuilds a forecast for every night of history on every
    /// metric -- it is the most expensive thing on this screen by a wide
    /// margin, and a computed property would re-run it on every render.
    @State private var reliability: [CalibrationLedger.Result] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("A wrist temperature is a thing a sensor recorded. A REM minute-count is a model's guess. Both look the same on a card, so here is which is which.")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
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

                if !reliability.isEmpty {
                    reliabilitySection.entrance(3)
                }

                ForEach(Array(SensorTruth.all.enumerated()), id: \.element.id) { index, fact in
                    row(fact).entrance(min(index + 4, 6))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .task(id: coordinator.recentNights.count) {
            // Off the main actor: `SleepNightFeatures` is `Sendable` and the
            // ledger is pure, so the whole backtest can run away from the
            // render thread and land back here as a plain array.
            let nights = coordinator.recentNights
            reliability = await Task.detached { CalibrationLedger.backtestAll(nights: nights) }.value
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
                .foregroundStyle(Theme.inkSecondary)
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
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Has the range been holding?

    /// The third question, and the one nothing in the app answered until now.
    ///
    /// The two sections above are about *inputs*: what kind of claim each
    /// number is, and whether this watch supplies it. This is about Zoon's
    /// own output. Every night it draws a range it expects tonight to land
    /// inside; `CalibrationLedger` walks the history, rebuilds each of those
    /// ranges from the nights before it only, and counts how often the night
    /// actually landed inside.
    ///
    /// It belongs on this screen rather than a new one because it answers the
    /// same question the screen exists for -- how much of this should I
    /// believe -- about the last thing that had no answer.
    @ViewBuilder
    private var reliabilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(Theme.text(13, weight: .semibold))
                    .foregroundStyle(Theme.Metric.sleep)
                Text(CalibrationLedger.title)
                    .font(Theme.label(15, weight: .semibold))
            }

            Text(CalibrationLedger.subtitle)
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(reliability.enumerated()), id: \.element.id) { index, result in
                if index > 0 {
                    Divider().overlay(Theme.neutral(0.10))
                }
                reliabilityRow(result)
            }

            Text("Scored by rebuilding each range from the nights before it, so no night helped predict itself.")
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func reliabilityRow(_ result: CalibrationLedger.Result) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(result.metric.label.capitalizedFirst)
                    .font(Theme.text(13))
                Spacer(minLength: 8)
                // The counts, not only the verdict. Same reasoning as the
                // "26 of 30" in the coverage rows above: the word is the
                // summary, the pair is the thing someone can check.
                Text("\(result.hits) of \(result.attempts)")
                    .font(Theme.text(11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }

            reliabilityBar(result)

            Text(result.verdict.label)
                .font(Theme.text(11, weight: .semibold))
                .foregroundStyle(tint(result.verdict))

            Text(result.verdict.meaning)
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(result.metric.label). \(result.verdict.label). "
                + "Landed inside the range on \(result.hits) of \(result.attempts) scored nights. "
                + result.verdict.meaning
        )
    }

    /// Where coverage actually landed, against where it should be.
    ///
    /// A band and a target rather than a percentage, because the width is the
    /// finding as much as the position is. "Still learning" is not a hedge to
    /// be taken on trust here -- it is visibly a band wide enough to sit over
    /// the target and over most of the axis at the same time, which is what
    /// having too few nights looks like. A single number could not show that,
    /// and a single number is what made the old verdict read as a pass.
    private func reliabilityBar(_ result: CalibrationLedger.Result) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let lower = clampedFraction(result.coverageLower)
            let upper = clampedFraction(result.coverageUpper)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.neutral(0.10))

                // The interval.
                Capsule()
                    .fill(tint(result.verdict).opacity(0.55))
                    .frame(width: max(2, (upper - lower) * width))
                    .offset(x: lower * width)

                // Where it should be. Drawn over the band on purpose: a
                // target inside the band is the picture of "cannot be ruled
                // out", and a target outside it is the picture of a finding.
                Rectangle()
                    .fill(Theme.neutral(0.85))
                    .frame(width: 1.5)
                    .offset(x: clampedFraction(result.expectedCoverage) * width)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    /// The axis is a proportion. Both bounds are already inside 0...1 by
    /// construction -- Wilson is bounded there, and the block bootstrap takes
    /// percentiles of rates that are -- so this is a guard against a future
    /// estimator, not a fix for the present one. `CalibrationLedgerTests`
    /// holds the invariant on the ledger's side; drawing off the end of a
    /// track is a poor way to find out it broke.
    private func clampedFraction(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func tint(_ verdict: CalibrationLedger.Verdict) -> Color {
        switch verdict {
        case .matchesExpectation: Theme.Family.recovery
        // Amber, and the only verdict that gets it. This is the one that
        // asks the reader to do something -- read the band as narrower than
        // their real spread -- and the palette's muted attention colour is
        // exactly its weight. `tooCautious` is a roomier band than needed,
        // which is not a problem, so it stays in the ordinary sleep hue.
        case .tooConfident: Theme.Family.attention
        case .tooCautious: Theme.Family.sleep
        // The two waiting states share one neutral. They are not findings,
        // and colouring them would put them in the same visual language as
        // the three that are.
        case .stillLearning, .notEnoughYet: Theme.neutral(0.55)
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
                    .foregroundStyle(Theme.inkSecondary)
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
                    .foregroundStyle(Theme.inkSecondary)
            }

            if let note = row.note {
                Text(note)
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkTertiary)
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
                                    .foregroundStyle(Theme.inkTertiary)
                                Text(text)
                                    .font(Theme.text(11))
                                    .foregroundStyle(Theme.inkSecondary)
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
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.neutral(0.12), in: Capsule())
            }
            Text(note)
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
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
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // The limit is the reason this screen exists, so it is never
            // collapsed behind a disclosure.
            Text(fact.quantity.limit)
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if fact.isWeakenedByItsInputs, let first = fact.weakenedBy.first {
                Text("Shown as \(fact.provenance.label.lowercased()) because \(first.label.lowercased()) is.")
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkTertiary)
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
        case .selfReported: Theme.inkSecondary
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

import SwiftUI

/// "What affects your sleep?" — patterns in the user's own history, not
/// generic sleep-hygiene advice.
///
/// A dedicated screen for what used to be a handful of rows buried at the
/// bottom of the Journal tab. Four tabs, one per exposure state a logged
/// behaviour can honestly be in: a strong enough matched-pair signal to call
/// "helps" or "hurts"; tested with enough comparable nights but no effect
/// found; or logged too few times yet to say anything about at all. All
/// three non-obvious states are shown explicitly rather than left silently
/// absent -- "no effect" and "still learning" look identical from the
/// outside (both mean "nothing in Helps/Hurts") unless the app says which
/// one it actually is.
struct CauseFinderView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    private enum Tab: String, CaseIterable, Identifiable {
        case helps = "Helps", hurts = "Hurts", noEffect = "No link", learning = "Learning"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .helps: "arrow.up.right"
            case .hurts: "arrow.down.right"
            case .noEffect: "equal"
            case .learning: "hourglass"
            }
        }

        var tint: Color {
            switch self {
            case .helps: Theme.Family.recovery
            case .hurts: Theme.Family.attention
            case .noEffect: Theme.inkSecondary
            case .learning: Theme.Family.sleep
            }
        }
    }

    @State private var tab: Tab = .helps
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingExperimentPicker = false

    /// Computed once per `body` evaluation and threaded through, rather than
    /// each of `experimentSection`/`content` independently re-deriving it --
    /// this used to be a plain computed property both read separately,
    /// running `coordinator.journalObservations()` twice (and, depending on
    /// which tab was active, a full `JournalCorrelator` matched-pair pass
    /// alongside it) for the same render.
    private func observations() -> [JournalCorrelator.Observation] {
        coordinator.journalObservations()
    }

    var body: some View {
        let observations = observations()
        return ScrollView {
            CascadeStack(alignment: .leading, spacing: Theme.stackSpacing) {
                header
                experimentSection(observations)
                pastExperimentsSection

                let groups = Groups(observations: observations, catalog: coordinator.behaviorCatalog)
                scoreboard(groups)
                content(groups)
                RelatedReading(placement: .behaviours, title: "On habits and sleep")
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Cause Finder")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExperimentPicker) {
            ExperimentPickerSheet { tag, hypothesis, primaryMetric, direction, design in
                preferences.startExperiment(
                    tag, hypothesis: hypothesis, primaryMetric: primaryMetric,
                    direction: direction, design: design
                )
                showingExperimentPicker = false
            }
        }
    }

    /// Active Guided Experiment, or a prompt to start one. See
    /// `GuidedExperiment` -- this doesn't run any statistics of its own,
    /// just reads the same findings/stillLearning/testedNoEffect results
    /// the tabs below already compute, filtered to one tracked tag.
    @ViewBuilder
    private func experimentSection(_ observations: [JournalCorrelator.Observation]) -> some View {
        if let tag = preferences.activeExperimentTag {
            GuidedExperimentCard(
                tag: tag,
                startDate: preferences.experimentStartDate,
                direction: preferences.experimentDirection ?? .avoid,
                // Which arm tonight belongs to, decided when the trial
                // started. A crossover whose plan lives only in the database
                // is a crossover nobody can follow.
                tonight: preferences.experimentSchedule.first {
                    Calendar.current.isDateInToday($0.date)
                },
                status: GuidedExperiment.status(for: tag, observations: observations, since: preferences.experimentStartDate),
                observations: observations,
                primaryMetric: preferences.experimentPrimaryMetric ?? .sleepPerformance,
                onEnd: { coordinator.endActiveExperiment() }
            )
        } else {
            // The point of this tab is testing a habit, so the way in is a
            // card rather than a small link above four tabs of findings.
            Button {
                Haptics.select()
                showingExperimentPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "flask.fill")
                        .font(Theme.text(18, weight: .semibold))
                        .foregroundStyle(Theme.Family.sleep)
                        .frame(width: 44, height: 44)
                        .background(Theme.Family.sleep.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Test a habit")
                            .font(Theme.label(15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("Change one thing and see what your nights say.")
                            .font(Theme.text(12))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassCard()
        }
    }

    /// Completed experiments, most recent first -- a before/after snapshot
    /// taken at the moment each one ended (see `GuidedExperiment.summarize`).
    /// Hidden entirely once there's nothing to show, same as every other
    /// optional section on this screen.
    @ViewBuilder
    private var pastExperimentsSection: some View {
        if !coordinator.experiments.outcomes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Past experiments", systemImage: "clock.arrow.circlepath")
                ForEach(coordinator.experiments.outcomes) { outcome in
                    PastExperimentRow(outcome: outcome)
                }
            }
            .glassCard()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What affects your sleep?")
                .font(Theme.heading(20))
            Text("From your own nights. Linked, not proven.")
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    /// Every behaviour, sorted into the four states it can honestly be in.
    /// Worked out once per render so the scoreboard and the list below it
    /// agree.
    private struct Groups {
        let helps: [JournalCorrelator.Finding]
        let hurts: [JournalCorrelator.Finding]
        let noEffect: [BehaviorID]
        let learning: [JournalCorrelator.LearningTag]
        let comparisons: Int

        init(observations: [JournalCorrelator.Observation], catalog: BehaviorCatalog) {
            let correlator = JournalCorrelator()
            let findings = correlator.findings(from: observations, catalog: catalog)
            helps = findings.filter(\.isImprovement)
            hurts = findings.filter { !$0.isImprovement }
            noEffect = correlator.testedNoEffect(from: observations, catalog: catalog)
            learning = correlator.stillLearning(from: observations, catalog: catalog)
            comparisons = correlator.comparisonCount(from: observations, catalog: catalog)
        }

        func count(_ tab: Tab) -> Int {
            switch tab {
            case .helps: helps.count
            case .hurts: hurts.count
            case .noEffect: noEffect.count
            case .learning: learning.count
            }
        }
    }

    /// The four states as counts you can tap, in place of a segmented
    /// control whose labels said nothing about what was behind them. The
    /// split is the first answer: three helping, one hurting, five still
    /// learning.
    private func scoreboard(_ groups: Groups) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
            ForEach(Tab.allCases) { option in
                let selected = option == tab
                Button {
                    Haptics.select()
                    withAnimation(Motion.respecting(reduceMotion, Motion.tap)) { tab = option }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: option.symbol)
                            .font(Theme.text(12, weight: .bold))
                            .symbolEffect(.bounce, value: selected)
                        Text("\(groups.count(option))")
                            .font(Theme.heading(22))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(option.rawValue)
                            .font(Theme.text(11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? option.tint : Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? option.tint.opacity(0.16) : Theme.neutral(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? option.tint.opacity(0.5) : .clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.rawValue): \(groups.count(option))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func content(_ groups: Groups) -> some View {
        switch tab {
        case .helps:
            comparisonNote(groups.comparisons)
            if groups.helps.isEmpty {
                emptyState("Nothing clears the bar yet. Keep logging.")
            } else {
                ForEach(groups.helps) { CauseFinderRow(finding: $0) }
            }
        case .hurts:
            comparisonNote(groups.comparisons)
            if groups.hurts.isEmpty {
                emptyState("Nothing clears the bar. A good sign.")
            } else {
                ForEach(groups.hurts) { CauseFinderRow(finding: $0) }
            }
        case .noEffect:
            if groups.noEffect.isEmpty {
                emptyState("Nothing tested yet.")
            } else {
                // Said once for the list, not on every row.
                Text("No clear link so far. That isn't proof of no effect.")
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                let catalog = coordinator.behaviorCatalog
                ForEach(groups.noEffect, id: \.self) { behavior in
                    NoEffectRow(label: catalog.label(for: behavior), symbol: catalog.symbol(for: behavior))
                }
            }
        case .learning:
            if groups.learning.isEmpty {
                emptyState("Tag a habit in the Journal and it shows up here while Zoon gathers nights.")
            } else {
                ForEach(groups.learning) { LearningRow(tag: $0) }
            }
        }
    }

    /// How many comparisons were run, so one striking finding can be weighed
    /// against the number of places Zoon looked. See
    /// `JournalCorrelator.comparisonCount`.
    @ViewBuilder
    private func comparisonNote(_ count: Int) -> some View {
        if count > 1 {
            Label("\(count) pairs checked. A few may be chance.", systemImage: "die.face.3")
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(Theme.text(12))
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
    }
}

/// One finding. Collapsed, it is the headline and a compact delta strip;
/// expanded, it is the full paired plot -- every matched pair, both ends,
/// connectors drawn in -- with the statistics that came out of them
/// underneath. The plot is the point of the screen (the redesign's "true
/// data visualizations, not generic bars"), so it is not wrapped in another
/// card of its own; the row's single container is enough grouping.
private struct CauseFinderRow: View {
    let finding: JournalCorrelator.Finding
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        finding.isImprovement ? Theme.Family.recovery : Theme.Family.attention
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Motion.respecting(reduceMotion, Motion.tap)) { expanded.toggle() }
                Haptics.select()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: finding.symbol)
                        .foregroundStyle(tint)
                        .frame(width: 24, height: 24)
                        .background(tint.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(finding.label)
                            .font(Theme.label(14, weight: .semibold))
                        Text("\(finding.metric.format(finding.delta)) \(finding.metric.shortLabel)")
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(finding.matchedPairCount.pluralized("matched night"))
                            .font(Theme.text(10))
                            .foregroundStyle(Theme.inkTertiary)
                        ZoonEvidenceBadge(confidence: ZoonPairedPlot.metricConfidence(finding.confidence))
                    }
                    Image(systemName: "chevron.down")
                        .font(Theme.text(10, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Collapses the paired plot." : "Expands to show every matched pair.")

            if expanded {
                if finding.pairs.count >= 2 {
                    ZoonPairedPlot(finding: finding, tint: tint)
                        .transition(.opacity)
                }
                Text(finding.detail)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if finding.pairDeltas.count >= 2 {
                // Collapsed: the compact one-line delta strip keeps the shape
                // of the evidence visible without the row growing tall.
                PairedDotPlot(deltas: finding.pairDeltas, tint: tint)
                    .transition(.opacity)
            }
        }
        .glassCard()
    }
}

/// A behaviour still gathering nights: one dot per night it needs, filled
/// for the nights it has. Counting dots replaced a bar and a sentence that
/// said the same thing in words.
private struct LearningRow: View {
    let tag: JournalCorrelator.LearningTag
    @State private var progress: Double = 0

    var body: some View {
        let needed = JournalCorrelator.minimumMatchedPairs
        let have = min(tag.loggedNights, needed)
        HStack(spacing: 10) {
            Image(systemName: tag.symbol)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 28, height: 28)
                .background(Theme.neutral(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(tag.label)
                    .font(Theme.label(14, weight: .semibold))
                HStack(spacing: 4) {
                    ForEach(0..<needed, id: \.self) { index in
                        let lit = index < have && progress * Double(needed) > Double(index)
                        Circle()
                            .fill(lit ? Theme.Family.sleep : Theme.neutral(0.12))
                            .frame(width: 8, height: 8)
                            .scaleEffect(lit ? 1 : 0.85)
                    }
                }
                .drawOnce(id: have, progress: $progress)
            }
            Spacer(minLength: 8)
            Text(tag.remainingNights == 0 ? "Ready" : "\(tag.remainingNights) to go")
                .font(Theme.text(11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.inkTertiary)
        }
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tag.label): \(have) of \(needed) nights logged")
    }
}

private struct NoEffectRow: View {
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 28, height: 28)
                .background(Theme.neutral(0.06), in: Circle())
            Text(label)
                .font(Theme.label(14, weight: .semibold))
            Spacer()
            Image(systemName: "equal.circle")
                .foregroundStyle(Theme.inkTertiary)
                .accessibilityHidden(true)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): no clear link")
    }
}

/// The active experiment: what is being tested, the day-by-day trial
/// ribbon, and the state of the answer. The ribbon replaced a "Logged 5 of
/// 8 days" line and a plain progress bar -- the same facts, but as a
/// pattern the eye reads rather than a ratio it has to compute.
private struct GuidedExperimentCard: View {
    let tag: BehaviorTag
    let startDate: Date?
    let direction: GuidedExperiment.Direction
    /// Tonight's assignment, when the trial has a schedule. `nil` for a
    /// before/after trial, which assigns nothing, and once the planned
    /// stretches have run out.
    var tonight: ExperimentDesign.Assignment?
    let status: GuidedExperiment.Status
    let observations: [JournalCorrelator.Observation]
    let primaryMetric: JournalCorrelator.Metric
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "flask.fill")
                    .foregroundStyle(Theme.Family.sleep)
                    .frame(width: 24, height: 24)
                    .background(Theme.Family.sleep.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Current experiment")
                        .font(Theme.kicker)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSecondary)
                    Text("\(direction == .avoid ? "Less" : "More") \(tag.label.lowercased())")
                        .font(Theme.label(15, weight: .semibold))
                    Text("Judged on \(primaryMetric.shortLabel)")
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.inkSecondary)
                    // Never "Tonight: with alcohol". A behaviour that may only
                    // be cut back is never on an assigned schedule (see
                    // `ExperimentDesign.allowed(for:)`); this is the last
                    // line of defence if one ever reaches the card.
                    if let tonight, tag.exposureControl == .eitherDirection {
                        // The whole value of assigning nights in advance is
                        // that the person can read tonight's off a screen
                        // instead of deciding it in the moment.
                        Label(
                            tonight.arm == .with
                                ? "Tonight: with \(tag.label.lowercased())"
                                : "Tonight: without \(tag.label.lowercased())",
                            systemImage: tonight.arm == .with ? "checkmark.circle" : "circle.slash"
                        )
                        .font(Theme.text(11, weight: .semibold))
                        .foregroundStyle(Theme.Family.sleep)
                    }
                }
                Spacer()
            }

            if let startDate {
                ZoonTrialRibbon(
                    tag: tag,
                    startDate: startDate,
                    direction: direction,
                    observations: observations
                )
            }

            DisclosureGroup("Logging plan and night coverage") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Answer Yes or No for \(tag.label.lowercased()) each day. Also log travel and illness.")
                    Text("A test on your own nights. \"Inconclusive\" means the data couldn't tell.")
                        .foregroundStyle(Theme.inkSecondary)
                    ForEach(observations.filter { $0.date >= (startDate ?? .distantPast) }.sorted { $0.date > $1.date }, id: \.date) { observation in
                        VStack(alignment: .leading) {
                            Text(observation.date, style: .date)
                            Text(observation.exposureState(for: tag) == .unknown ? "Not comparable: no explicit answer" : primaryMetric.value(from: observation) == nil ? "Not comparable: missing outcome" : "Answer and outcome recorded; matching still depends on context")
                                .font(.caption).foregroundStyle(Theme.inkSecondary)
                            if observation.isTravelDay { Text("Travel context").font(.caption) }
                        }
                    }
                }.font(.callout)
            }

            switch status {
            case .learning(let learning):
                Text("Needs about \(learning.remainingNights.pluralized("more comparable night")) before there's an answer. Keep tagging \(tag.label.lowercased()) in the Journal.")
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

            case .result(let helpful, let harmful):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Early result")
                        .font(Theme.kicker)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSecondary)
                    ForEach(helpful + harmful) { finding in
                        HStack(spacing: 8) {
                            Image(systemName: finding.isImprovement ? "arrow.up.right" : "arrow.down.right")
                                .font(Theme.text(10, weight: .bold))
                            Text(finding.headline)
                                .font(Theme.text(12, weight: .semibold))
                        }
                        .foregroundStyle(finding.isImprovement ? Theme.Family.recovery : Theme.Family.attention)
                    }
                }

            case .noEffect:
                Text("No clear association in your data so far. That is not evidence of no effect.")
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Button("End experiment", action: onEnd)
                .font(Theme.text(11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .glassCard()
    }
}

private struct ExperimentPickerSheet: View {
    let onSelect: (BehaviorTag, String?, JournalCorrelator.Metric, GuidedExperiment.Direction, ExperimentDesign) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hypothesis: String = ""
    @State private var primaryMetric: JournalCorrelator.Metric = .sleepPerformance
    @State private var direction: GuidedExperiment.Direction = .avoid
    /// Four stretches in a fixed-in-advance order is the design worth
    /// defaulting to: it is the only one on the list that cancels a steady
    /// drift out of the answer, and it costs the same weeks as the others.
    @State private var design: ExperimentDesign = .abba

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Shape of the trial", selection: $design) {
                        ForEach(ExperimentDesign.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } footer: {
                    if design.isControlled {
                        Text(design.rationale + " About \(design.plannedNights()) nights. Alcohol, nicotine, cannabis, caffeine and sleep aids are always tested as a before and after of cutting back, because this shape would schedule nights with them.")
                    } else {
                        Text(design.rationale + " About \(design.plannedNights()) nights.")
                    }
                }
                Section {
                    Picker("This experiment is about", selection: $direction) {
                        ForEach(GuidedExperiment.Direction.allCases, id: \.self) { direction in
                            Text(direction.label).tag(direction)
                        }
                    }
                    .adaptiveSegmentedStyle()
                } footer: {
                    Text("Decides which nights count. Zoon only ever suggests cutting back on alcohol, nicotine, cannabis, late caffeine and sleep aids.")
                }
                Section {
                    TextField("What do you expect to find? (optional)", text: $hypothesis, axis: .vertical)
                        .lineLimit(1...3)
                } footer: {
                    Text("Just for you. It never changes the result.")
                }
                Section {
                    Picker("Judge the result on", selection: $primaryMetric) {
                        ForEach(JournalCorrelator.Metric.allCases, id: \.self) { metric in
                            Text(metric.shortLabel.capitalized).tag(metric)
                        }
                    }
                } footer: {
                    Text("Picked before the data, so the result can't be cherry-picked.")
                }
                // Only behaviours this direction may be tested in. Zoon does
                // not ask anybody to drink, smoke or take more of a sleep aid
                // to see what it does -- and it does not offer a trial of
                // being unwell or of travelling, which nobody assigns
                // themselves either way. See `BehaviorTag.ExposureControl`.
                ForEach(BehaviorTag.Category.allCases) { category in
                    let testable = category.tags.filter { $0.testableDirections.contains(direction) }
                    if !testable.isEmpty {
                        Section(category.label) {
                            ForEach(testable) { tag in
                                Button {
                                    onSelect(tag, hypothesis, primaryMetric, direction, design)
                                } label: {
                                    Label(tag.label, systemImage: tag.symbol)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Track a behaviour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct PastExperimentRow: View {
    let outcome: SleepExperimentStore.Outcome
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tag: BehaviorTag? { BehaviorTag(rawValue: outcome.tag) }

    private var tint: Color {
        outcome.isImprovement ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Motion.respecting(reduceMotion, Motion.tap)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    if let tag {
                        Image(systemName: tag.symbol)
                            .foregroundStyle(tint)
                            .frame(width: 22, height: 22)
                            .background(tint.opacity(0.15), in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tag?.label ?? outcome.tag)
                            .font(Theme.label(13, weight: .semibold))
                        Text(outcome.startDate, format: .dateTime.month(.abbreviated).day())
                            + Text(" – ")
                            + Text(outcome.endDate, format: .dateTime.month(.abbreviated).day())
                    }
                    .font(Theme.text(10))
                    .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(Theme.text(10, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let hypothesis = outcome.hypothesis, !hypothesis.isEmpty {
                        Text("Hypothesis: \(hypothesis)")
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Text("""
                        Comparing \(outcome.baselineNightCount) nights before the trial against \
                        \(outcome.trialCompliantNightCount.map(String.init) ?? "\(outcome.trialNightCount)") \
                        adherent nights during it, \(outcome.metricLabel) went from a \
                        typical \(String(format: "%.0f", outcome.baselineMedian)) to \
                        \(String(format: "%.0f", outcome.trialMedian)). A before/after comparison, not a \
                        controlled one -- other things could have changed too.
                        """)
                        .font(Theme.text(12))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Logged is not measured. The medians above rest on the
                    // nights where the metric actually arrived, and when
                    // that is fewer than the nights logged the reader is
                    // told, not left to assume every night counted.
                    if let baselineUsable = outcome.baselineUsableCount,
                       let trialUsable = outcome.trialUsableCount {
                        Text("Measured on \(baselineUsable) of \(outcome.baselineNightCount) baseline nights and \(trialUsable) of \(outcome.trialCompliantNightCount ?? outcome.trialNightCount) trial nights.")
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let baselineDates = outcome.baselineNightDates,
                       let trialDates = outcome.trialNightDates {
                        // What counted, not only how many: the nights the
                        // two medians above were computed from.
                        DisclosureGroup("Which nights counted") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Before: \(EvidenceNights.list(baselineDates))")
                                Text("During: \(EvidenceNights.list(trialDates))")
                            }
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(Theme.text(12, weight: .medium))
                        .tint(Theme.ink)
                    }
                    if let adherenceRate = outcome.adherenceRate, let compliant = outcome.trialCompliantNightCount, let direction = outcome.direction {
                        // "The rest" used to be one bucket. It is two, and
                        // they mean different things: a night that broke the
                        // plan says the plan was hard to keep, a night nobody
                        // logged says nothing about the plan at all.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(direction == .avoid ? "Stuck to it" : "Followed through") \(compliant) of \(outcome.trialNightCount) trial nights (\(Int((adherenceRate * 100).rounded()))%).")
                            if let breakdown = outcome.adherenceBreakdown {
                                Text(breakdown.sentence.capitalizedFirst + ".")
                            }
                        }
                        .font(Theme.text(10))
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    } else if let known = outcome.trialKnownNightCount {
                        Text("Logged \(known) of \(outcome.trialNightCount) trial nights either way -- the rest never got tagged, so the result rests on the ones that did.")
                            .font(Theme.text(10))
                            .foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

#Preview("Cause Finder") {
    NavigationStack { CauseFinderView() }
        .zoonPreviewEnvironment()
}

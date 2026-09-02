import SwiftUI

/// Everything Zoon thinks it knows about you, sorted by how it came to know
/// it.
///
/// The rest of the app is organised by subject -- sleep here, body signals
/// there, causes in Cause Finder. That is the right shape for looking
/// something up and the wrong shape for the question people actually ask,
/// which is "how much of this should I believe?". A tested result and a
/// single odd night both surface as a sentence on a card, and nothing about
/// where they sit tells you which is which.
///
/// This screen is organised by strength instead. `EvidenceNotebook` does the
/// grading; this renders the four tiers in order, weakest last, with each
/// tier's caveat attached to the tier rather than buried in a detail sheet.
/// A claim's rank is the first thing you see, not something you have to go
/// looking for.
struct EvidenceView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        ScrollView {
            // Computed once and passed down. `journalObservations()` walks
            // the whole history and the correlator runs a matched-pair
            // search over it; both the planner and the notebook need the
            // same answer, and CauseFinderView documents the same hazard.
            let observations = coordinator.journalObservations()
            let findings = JournalCorrelator().findings(from: observations)

            LazyVStack(alignment: .leading, spacing: 18) {
                nextExperiment(observations: observations, findings: findings)
                    .entrance(0)

                sensorTruthLink.entrance(0)

                ledgers(observations: observations, findings: findings)
                    .entrance(1)

                let entries = notebookEntries(findings: findings)
                if entries.isEmpty {
                    emptyState.entrance(1)
                } else {
                    ForEach(Array(tiers(of: entries).enumerated()), id: \.element.strength) { index, tier in
                        tierSection(tier)
                            .entrance(index + 1)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("What Zoon knows")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Data

    /// Moved to the coordinator so the watch's headline claim and this
    /// screen's top row come out of one compilation. Only last night is
    /// investigated there, for the reason that comment records: running
    /// `NightDetective` across a history would manufacture a stream of
    /// anecdotes, the weakest tier flooding the strongest ones off the
    /// screen.
    private func notebookEntries(
        findings: [JournalCorrelator.Finding]
    ) -> [EvidenceNotebook.Entry] {
        coordinator.notebookEntries(findings: findings)
    }

    private struct Tier {
        let strength: EvidenceNotebook.Strength
        let entries: [EvidenceNotebook.Entry]
    }

    /// Groups without re-sorting: `EvidenceNotebook.compile` already returns
    /// strongest first, so walking it in order and starting a new tier at
    /// each change preserves both the tier order and the recency order
    /// inside each tier.
    private func tiers(of entries: [EvidenceNotebook.Entry]) -> [Tier] {
        var result: [Tier] = []
        for entry in entries {
            if let last = result.last, last.strength == entry.strength {
                result[result.count - 1] = Tier(
                    strength: last.strength, entries: last.entries + [entry]
                )
            } else {
                result.append(Tier(strength: entry.strength, entries: [entry]))
            }
        }
        return result
    }

    // MARK: - Sections

    @ViewBuilder
    private func tierSection(_ tier: Tier) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol(for: tier.strength))
                    .font(Theme.text(13, weight: .semibold))
                    .foregroundStyle(tint(for: tier.strength))
                Text(title(for: tier.strength))
                    .font(Theme.label(13, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
            }

            ForEach(tier.entries) { entry in
                entryRow(entry, tint: tint(for: tier.strength))
            }

            // Attached to the tier, not to each claim: it is the same caveat
            // for everything at this rank, and repeating it per row would
            // train people to skip it.
            Text(tier.strength.caveat)
                .font(Theme.text(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func entryRow(_ entry: EvidenceNotebook.Entry, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.headline)
                    .font(Theme.text(14))
                    .fixedSize(horizontal: false, vertical: true)
                if let confidence = entry.confidence {
                    Text(confidence.label)
                        .font(Theme.text(11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Belief history

    /// The behaviours whose belief has moved furthest, each as a dated ledger.
    ///
    /// Picks the tags that have progressed past "suspected": an association
    /// the correlator found, a trial that was run, or a trial that is
    /// running. Capped at three -- the ledger exists to show *how* a belief
    /// formed, and that reading takes attention a list of twelve would
    /// exhaust. Everything else still appears in the tiers below.
    @ViewBuilder
    private func ledgers(
        observations: [JournalCorrelator.Observation],
        findings: [JournalCorrelator.Finding]
    ) -> some View {
        let candidates = ledgerTags(findings: findings)
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 24) {
                ZoonSectionHeader("How Zoon got here")

                ForEach(candidates, id: \.self) { tag in
                    let outcomes = coordinator.experiments.outcomes.filter { $0.tag == tag.rawValue }
                    let active: (startDate: Date, direction: GuidedExperiment.Direction)? = {
                        guard preferences.activeExperimentTag == tag, let start = preferences.experimentStartDate else { return nil }
                        return (start, preferences.experimentDirection ?? .avoid)
                    }()
                    if let milestones = ZoonEvidenceLedger.milestones(
                        for: tag,
                        observations: observations,
                        finding: findings.first { $0.tag == tag },
                        activeExperiment: active,
                        outcomes: outcomes
                    ) {
                        ZoonEvidenceLedger(tag: tag, milestones: milestones)
                    }
                }
            }
        }
    }

    /// Tested first (strongest belief), then the active trial, then
    /// associations by confidence -- the order the tiers below use.
    private func ledgerTags(findings: [JournalCorrelator.Finding]) -> [BehaviorTag] {
        var ordered: [BehaviorTag] = []
        for outcome in coordinator.experiments.outcomes.sorted(by: { $0.endDate > $1.endDate }) {
            if let tag = BehaviorTag(rawValue: outcome.tag), !ordered.contains(tag) { ordered.append(tag) }
        }
        if let active = preferences.activeExperimentTag, !ordered.contains(active) {
            ordered.append(active)
        }
        for finding in findings.sorted(by: { Self.rank($0.confidence) > Self.rank($1.confidence) }) {
            if !ordered.contains(finding.tag) { ordered.append(finding.tag) }
        }
        return Array(ordered.prefix(3))
    }

    /// `Confidence` is a `String` enum; sorting by its raw value would put
    /// "high" before "low" alphabetically.
    private static func rank(_ confidence: JournalCorrelator.Confidence) -> Int {
        switch confidence {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }

    @ViewBuilder
    private func nextExperiment(
        observations: [JournalCorrelator.Observation],
        findings: [JournalCorrelator.Finding]
    ) -> some View {
        if let proposal = ExperimentPlanner.next(
            observations: observations,
            associatedTags: Set(findings.map(\.tag)),
            settledTags: Set(coordinator.experiments.outcomes.map(\.tag))
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(proposal.headline)
                    .font(Theme.label(16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(proposal.sentence)
                    .font(Theme.text(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(proposal.caveat)
                    .font(Theme.text(11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    /// One level further down from this screen's question. Evidence grades
    /// the claims Zoon makes; that screen grades the numbers those claims
    /// are built from, which is the natural next "how much of this should I
    /// believe".
    private var sensorTruthLink: some View {
        NavigationLink {
            SensorTruthView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.Metric.strain)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Where the numbers come from")
                        .font(Theme.label(14, weight: .semibold))
                    Text("Which are measured, and which are estimates")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        Text("Nothing worth claiming yet. A few more nights, and anything Zoon finds will show up here ranked by how it found it.")
            .font(Theme.text(13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }

    // MARK: - Tier presentation

    private func title(for strength: EvidenceNotebook.Strength) -> String {
        switch strength {
        case .tested: "You tested this"
        case .associated: "Your nights suggest"
        case .observed: "Something changed"
        case .anecdote: "One night"
        }
    }

    private func symbol(for strength: EvidenceNotebook.Strength) -> String {
        switch strength {
        case .tested: "checkmark.seal.fill"
        case .associated: "link"
        case .observed: "chart.line.uptrend.xyaxis"
        case .anecdote: "moon.zzz.fill"
        }
    }

    /// Deliberately cooling as the claims weaken, so the ranking is legible
    /// before any of the words are read.
    private func tint(for strength: EvidenceNotebook.Strength) -> Color {
        switch strength {
        case .tested: Theme.Metric.recoveryHigh
        case .associated: Theme.Metric.sleep
        case .observed: Theme.Metric.strain
        case .anecdote: .secondary
        }
    }
}

#Preview("What Zoon knows") {
    NavigationStack { EvidenceView() }
        .zoonPreviewEnvironment()
}

/// The densest of the four new screens, and the last one without a large-text
/// preview. Two places to look: the tier headers, where an icon sits beside
/// uppercased kerned text on one line, and the claim rows, where the bullet
/// is pinned six points down from the top of a headline that gets much
/// taller here -- fine against one line, adrift against three.
#Preview("What Zoon knows - large text") {
    NavigationStack { EvidenceView() }
        .zoonPreviewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

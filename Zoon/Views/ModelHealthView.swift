import SwiftUI

/// "How well does Zoon know me?" -- one ladder, seven areas, no score.
///
/// The dominant visual is deliberately a single ladder rather than a stack of
/// cards, following the V10 rule that each screen gets one visual language.
/// Every area sits on the same four-step track, so the shape of the page is
/// the answer: a ragged left edge means one part is holding the rest back,
/// and a straight one means everything is at the same point. That is a thing
/// the eye reads in a second and a list of percentages is not.
///
/// The word "score" appears nowhere, and neither does a number out of a
/// hundred. See `ModelHealth` for why.
struct ModelHealthView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    @State private var assessments: [ModelHealth.Assessment] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                if assessments.isEmpty {
                    ContentUnavailableView(
                        "Nothing to describe yet",
                        systemImage: "questionmark.circle",
                        description: Text("Once Zoon has a few nights, this page will say which parts of what it knows are settled and which are still forming.")
                    )
                    .padding(.top, 40)
                } else {
                    header
                    ladder
                    method
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("How well Zoon knows you")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: coordinator.recentNights.count) {
            // The calibration backtest re-forecasts every past night for
            // every metric. Off the main actor, the same way `SensorTruthView`
            // runs it, and once per change in the night count rather than on
            // every redraw.
            let nights = coordinator.recentNights
            let verdict = await Task.detached {
                CalibrationLedger.backtestAll(nights: nights)
                    .first { $0.verdict.isDecisive }?
                    .verdict
            }.value
            // The best-supported matched comparison across the levers, or
            // nil when none is supported. `estimate` refuses far more often
            // than it succeeds by design, and a refusal here is the honest
            // reading: Zoon cannot yet find nights like yours to compare.
            // Six estimates -- three levers, two directions -- each with its
            // own matching pass and bootstrap. Detached and keyed on the
            // night count, so this runs when a night arrives and not on a
            // redraw.
            let pairs = await Task.detached { () -> Int? in
                var best: Int?
                for lever in ZoonTwin.levers {
                    for direction in [ZoonTwin.Direction.more, .less] {
                        let result = ZoonTwinV2.estimate(
                            nights: nights, lever: lever, direction: direction
                        )
                        if let count = result.estimate?.pairs {
                            best = max(best ?? 0, count)
                        }
                    }
                }
                return best
            }.value
            assessments = build(calibration: verdict, pairs: pairs)
        }
    }

    // MARK: - Header

    private var header: some View {
        let stage = ModelHealth.overall(assessments)
        return VStack(alignment: .leading, spacing: 8) {
            Text(stage.label)
                .font(Theme.numeral(28))
                .foregroundStyle(tint(for: stage))
            Text(stage.meaning)
                .font(Theme.text(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ModelHealth.headline(assessments))
                .font(Theme.text(12))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overall, \(stage.label). \(ModelHealth.headline(assessments))")
    }

    // MARK: - The ladder

    private var ladder: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Area by area", systemImage: "square.stack.3d.up")
            ForEach(Array(assessments.enumerated()), id: \.element.id) { index, assessment in
                if index > 0 {
                    Divider().overlay(Theme.cardStroke)
                }
                row(assessment)
            }
        }
        .glassCard()
    }

    private func row(_ assessment: ModelHealth.Assessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: assessment.area.symbol)
                    .font(Theme.text(12))
                    .frame(width: 18)
                    .foregroundStyle(tint(for: assessment.stage))
                Text(assessment.area.label)
                    .font(Theme.label(14, weight: .semibold))
                Spacer(minLength: 8)
                Text(assessment.stage.label)
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(tint(for: assessment.stage))
            }

            steps(assessment.stage)

            Text(assessment.area.question)
                .font(Theme.text(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(assessment.basis)
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(assessment.area.label), \(assessment.stage.label). \(assessment.basis)."
        )
    }

    /// Four segments, filled up to the stage reached.
    ///
    /// Segments rather than a continuous bar, because a bar invites reading a
    /// position off it -- "about 70% known" -- which is the score this screen
    /// exists to avoid. Four discrete steps can only be counted.
    private func steps(_ stage: ModelHealth.Stage) -> some View {
        HStack(spacing: 4) {
            ForEach(ModelHealth.Stage.allCases, id: \.self) { step in
                Capsule()
                    .fill(step <= stage ? tint(for: stage) : Theme.neutral(0.14))
                    .frame(height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Method

    private var method: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How this is worked out", systemImage: "info.circle")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("""
                Each area is placed on the same four steps by how much is behind it -- nights, readings, \
                settled findings, matched pairs. Nothing here is averaged into one number: the step at the \
                top is the *weakest* area, not the middle of them, because a gap in what Zoon knows is more \
                useful to see than a figure that hides it.
                """)
                .font(Theme.text(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func tint(for stage: ModelHealth.Stage) -> Color {
        switch stage {
        case .learning: Theme.neutral(0.55)
        case .establishing: Theme.Family.attention
        case .personalised: Theme.Family.sleep
        case .wellEstablished: Theme.Family.recovery
        }
    }

    // MARK: - Gathering what the rest of the app already decided

    /// Reads the counts off the coordinator. Nothing is recomputed here --
    /// see `ModelHealth`'s doc comment on why this must not become a second
    /// opinion.
    private func build(
        calibration: CalibrationLedger.Verdict?,
        pairs: Int?
    ) -> [ModelHealth.Assessment] {
        let nights = coordinator.recentNights
        guard !nights.isEmpty else { return [] }

        // A claim counts as settled once its most recent revision stands at
        // `.associated` or stronger. The current status, not any status it
        // ever held: the ledger is append-only, so a claim that was
        // associated and is now inconclusive still has the old revision in
        // it, and counting that would make the model look better the more
        // often it changed its mind.
        let history = EvidenceLedgerStore(context: modelContext).allRevisions()
        let settled = EvidenceLedger.claimIDs(in: history).filter { id in
            guard let latest = EvidenceLedger.timeline(for: id, in: history).last else { return false }
            return Self.settledStatuses.contains(latest.status)
        }.count

        return ModelHealth.assess(
            nightCount: nights.count,
            // The learned need's own count, read off the day context the
            // coordinator already built -- `state` is published before
            // `recentNights`, so it is there by the time this task runs.
            qualifyingSleepNeedNights: coordinator.state.context?.learnedSleepNeed.qualifyingNightCount ?? 0,
            nightsWithRecoverySignal: nights.filter { $0.avgHRV != nil }.count,
            nightsWithBodySignals: nights.filter { $0.restingHeartRate != nil }.count,
            coverage: coverage(of: nights),
            settledClaims: settled,
            calibration: calibration,
            matchedPairs: pairs
        )
    }

    /// The statuses that count as a habit having shown up in someone's own
    /// nights. `.observed` is deliberately not among them: it is a contrast
    /// between two sets of nights that differ in every other way, which is
    /// why the ledger gave it its own case below `.associated`.
    private static let settledStatuses: Set<EvidenceLedger.Status> = [
        .associated, .testing, .supported, .notSupported
    ]

    /// The share of the readings Zoon looks for that actually arrived, over
    /// the nights it holds.
    ///
    /// Counted over four measurements rather than every field on the record:
    /// these are the ones whose absence changes what the app can say, and
    /// padding the denominator with fields that are always present would make
    /// every coverage figure look better than it is.
    private func coverage(of nights: [SleepNightFeatures]) -> Double? {
        guard nights.count >= SourceCoverage.minimumNights else { return nil }
        let checks: [(SleepNightFeatures) -> Bool] = [
            { $0.avgHRV != nil },
            { $0.restingHeartRate != nil },
            { $0.avgRespiratoryRate != nil },
            { $0.coreMinutes + $0.deepMinutes + $0.remMinutes > 0 }
        ]
        let present = nights.reduce(0) { total, night in
            total + checks.filter { $0(night) }.count
        }
        return Double(present) / Double(nights.count * checks.count)
    }
}

#Preview("How well Zoon knows you") {
    NavigationStack { ModelHealthView() }
        .zoonPreviewEnvironment()
}

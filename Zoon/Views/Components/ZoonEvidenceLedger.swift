import SwiftUI

/// How Zoon came to believe what it believes about one behaviour, as a dated
/// history rather than a single current verdict.
///
/// ```
/// LATE CAFFEINE
///
/// ● Feb 03   Suspected
/// │
/// ● Feb 21   Association detected · +11m latency
/// │
/// ● Mar 04   Experiment started
/// │
/// ● Mar 19   Moderate evidence · +9m latency
/// ```
///
/// Nothing here is a new engine. Every milestone is read off records the
/// app already keeps -- the first night the tag was logged, the current
/// `JournalCorrelator` finding, the active or completed guided experiment --
/// and put in date order. The point is the *shape*: a belief that has moved
/// from "you mentioned this" through "your nights agree" to "you tested it"
/// is a different thing from one that has sat at "suspected" for months,
/// and a flat list of current claims cannot show which is which.
///
/// Milestones use `ZoonTimeline`'s spine so the Evidence screen and Tonight
/// speak the same visual language; here every node is in the past, so
/// there is no "now" marker and nothing is greyed as done.
struct ZoonEvidenceLedger: View {
    /// One entry in a behaviour's belief history.
    struct Milestone: Identifiable, Hashable {
        enum Kind: Hashable {
            /// First night the behaviour was logged at all.
            case suspected
            /// `JournalCorrelator` found a matched-pair association.
            case associated
            /// A guided experiment began.
            case experimentStarted
            /// A guided experiment ended with a result.
            case tested
        }

        let kind: Kind
        let date: Date
        let detail: String?

        var id: String { "\(kind)-\(date.timeIntervalSince1970)" }

        var title: String {
            switch kind {
            case .suspected: "Suspected"
            case .associated: "Association detected"
            case .experimentStarted: "Experiment started"
            case .tested: "You tested this"
            }
        }

        var symbol: String {
            switch kind {
            case .suspected: "questionmark.circle"
            case .associated: "link"
            case .experimentStarted: "flask"
            case .tested: "checkmark.seal.fill"
            }
        }
    }

    let tag: BehaviorTag
    let milestones: [Milestone]

    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sorted: [Milestone] { milestones.sorted { $0.date < $1.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tag.label)
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, milestone in
                    row(milestone, index: index, isLast: index == sorted.count - 1)
                }
            }
        }
        .drawOnce(id: sorted.map(\.id).joined(), progress: $progress)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tag.label), evidence history")
    }

    private func row(_ milestone: Milestone, index: Int, isLast: Bool) -> some View {
        let tint = Self.tint(for: milestone.kind)
        let revealed = progress >= Double(index) / Double(max(sorted.count, 1))
        return HStack(alignment: .top, spacing: 14) {
            Text(milestone.date, format: .dateTime.month(.abbreviated).day())
                .font(Theme.label(12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
                .padding(.top, 2)

            VStack(spacing: 0) {
                Circle()
                    .fill(tint)
                    .frame(width: isLast ? 12 : 9, height: isLast ? 12 : 9)
                    .frame(width: 14, height: 18)
                if !isLast {
                    Rectangle()
                        .fill(tint.opacity(0.35))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: milestone.symbol)
                        .font(Theme.text(11, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(milestone.title)
                        .font(Theme.label(14, weight: isLast ? .semibold : .medium))
                }
                if let detail = milestone.detail {
                    Text(detail)
                        .font(Theme.evidence)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)

            Spacer(minLength: 0)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 6)
        .animation(Motion.respecting(reduceMotion, .easeOut(duration: 0.25)), value: revealed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(milestone.date.formatted(.dateTime.month(.wide).day())), \(milestone.title)\(milestone.detail.map { ". \($0)" } ?? "")")
    }

    /// Warms as the belief strengthens -- the same progression the Evidence
    /// tiers use, so the ledger's last node matches the tier its claim sits
    /// in. Shape and title carry the meaning; this only reinforces it.
    static func tint(for kind: Milestone.Kind) -> Color {
        switch kind {
        case .suspected: Theme.neutral(0.45)
        case .associated: Theme.Family.sleep
        case .experimentStarted: Theme.Family.circadian
        case .tested: Theme.Family.recovery
        }
    }
}

// MARK: - Building the history

extension ZoonEvidenceLedger {
    /// Assembles one behaviour's milestones from what the app already keeps.
    ///
    /// - Parameters:
    ///   - observations: every journaled night; the first one tagged with
    ///     `tag` is the "suspected" date.
    ///   - finding: the current matched-pair association for the tag, if
    ///     the correlator produced one. It has no date of its own -- it
    ///     summarises a history -- so it is placed at the night its evidence
    ///     first cleared the correlator's minimum pair count, which is the
    ///     earliest date the association *could* have been detected.
    ///   - activeExperiment: an in-progress trial, if this tag is the one
    ///     being tested.
    ///   - outcomes: completed trials for this tag.
    ///
    /// Returns `nil` when the behaviour has never been logged: a ledger with
    /// no first entry is not a history.
    static func milestones(
        for tag: BehaviorTag,
        observations: [JournalCorrelator.Observation],
        finding: JournalCorrelator.Finding?,
        activeExperiment: (startDate: Date, direction: GuidedExperiment.Direction)?,
        outcomes: [SleepExperimentStore.Outcome]
    ) -> [Milestone]? {
        let tagged = observations
            .filter { $0.exposureState(for: tag) == .yes }
            .sorted { $0.date < $1.date }
        guard let first = tagged.first else { return nil }

        var result: [Milestone] = [
            Milestone(kind: .suspected, date: first.date, detail: "First logged in your Journal")
        ]

        if let finding {
            // The pairs are in matching order (tagged nights ascending), so
            // the Nth pair's date is when the Nth pair existed.
            let threshold = JournalCorrelator.minimumMatchedPairs
            let detectedAt = finding.pairs.count >= threshold
                ? finding.pairs[threshold - 1].date
                : finding.pairs.last?.date ?? first.date
            result.append(Milestone(
                kind: .associated,
                date: max(detectedAt, first.date),
                detail: "\(finding.metric.format(finding.delta)) \(finding.metric.shortLabel) · \(finding.matchedPairCount.pluralized("matched pair")) · \(finding.confidence.label)"
            ))
        }

        for outcome in outcomes.sorted(by: { $0.startDate < $1.startDate }) {
            let verb = outcome.direction == .avoid ? "Less" : "More"
            result.append(Milestone(
                kind: .experimentStarted,
                date: outcome.startDate,
                detail: "\(verb) \(tag.label.lowercased()) · judged on \(outcome.metricLabel)"
            ))
            let direction = outcome.isImprovement ? "improved" : "worsened"
            result.append(Milestone(
                kind: .tested,
                date: outcome.endDate,
                detail: "\(outcome.metricLabel.capitalizedFirst) \(direction) during your trial · \(outcome.trialNightCount.pluralized("trial night"))"
            ))
        }

        if let activeExperiment {
            let verb = activeExperiment.direction == .avoid ? "Less" : "More"
            result.append(Milestone(
                kind: .experimentStarted,
                date: activeExperiment.startDate,
                detail: "\(verb) \(tag.label.lowercased()) · in progress"
            ))
        }

        return result
    }
}

#Preview("Evidence ledger") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            ZoonEvidenceLedger(
                tag: .caffeineLate,
                milestones: [
                    .init(kind: .suspected, date: .now.addingTimeInterval(-86400 * 60), detail: "First logged in your Journal"),
                    .init(kind: .associated, date: .now.addingTimeInterval(-86400 * 42), detail: "−4% sleep efficiency · 12 matched pairs · Moderate confidence"),
                    .init(kind: .experimentStarted, date: .now.addingTimeInterval(-86400 * 30), detail: "Less caffeine after 4pm · judged on sleep efficiency"),
                    .init(kind: .tested, date: .now.addingTimeInterval(-86400 * 16), detail: "Sleep efficiency improved during your trial · 14 trial nights"),
                ]
            )
            ZoonEvidenceLedger(
                tag: .readBeforeBed,
                milestones: [
                    .init(kind: .suspected, date: .now.addingTimeInterval(-86400 * 20), detail: "First logged in your Journal"),
                ]
            )
        }
        .padding()
    }
    .nightBackground()
    .zoonPreviewEnvironment()
}

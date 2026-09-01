import SwiftUI

/// Discoveries as findings, not as a link to a feature.
///
/// Each finding is laid out as the spec asks: the behaviour, the effect in
/// plain words, the sample size, and an evidence badge -- with the
/// `PairedDotPlot` of its actual matched pairs as the visual signature. All
/// of it reads `JournalCorrelator.Finding` verbatim (`pairDeltas`,
/// `matchedPairCount`, `confidence`); nothing is re-derived.
///
/// Renders nothing until there is a finding or a running experiment, and
/// shows the learning state below the Cause Finder threshold instead.
struct DiscoveriesStream: View {
    let findings: [JournalCorrelator.Finding]
    var activeExperiment: (tag: BehaviorTag, status: GuidedExperiment.Status)?
    /// For the learning state when nothing has cleared the bar yet.
    var taggedNights: Int = 0

    private var top: [JournalCorrelator.Finding] {
        Array(
            findings.sorted {
                $0.confidence.rank == $1.confidence.rank
                    ? $0.matchedPairCount > $1.matchedPairCount
                    : $0.confidence.rank > $1.confidence.rank
            }
            .prefix(2)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZoonSectionHeader("Discoveries") {
                NavigationLink {
                    CauseFinderView()
                } label: {
                    HStack(spacing: 3) {
                        Text("Cause Finder")
                        Image(systemName: "chevron.right").font(Theme.text(10, weight: .semibold))
                    }
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.Family.sleep)
                }
                .buttonStyle(.plain)
            }

            if top.isEmpty && activeExperiment == nil {
                ZoonEmptyState(kind: .learning(
                    collected: taggedNights,
                    typicallyNeeded: JournalCorrelator.minimumMatchedPairs...(JournalCorrelator.minimumMatchedPairs * 2),
                    message: "Tag a few behaviours in the Journal. Once Zoon has enough comparable nights it will start exploring patterns."
                ))
                .padding(.vertical, -16)
            } else {
                ForEach(top) { finding in
                    NavigationLink { CauseFinderView() } label: { findingRow(finding) }
                        .buttonStyle(.plain)
                }
                if let activeExperiment {
                    ExperimentPreview(tag: activeExperiment.tag, status: activeExperiment.status)
                }
            }
        }
    }

    private func findingRow(_ finding: JournalCorrelator.Finding) -> some View {
        let tint = finding.isImprovement ? Theme.Family.recovery : Theme.Family.attention
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: finding.tag.symbol)
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(finding.tag.label)
                    .font(Theme.label(15, weight: .semibold))
                Spacer(minLength: 0)
                ZoonEvidenceBadge(confidence: Self.metricConfidence(finding.confidence))
            }

            Text(effectSentence(finding))
                .font(Theme.text(14))
                .fixedSize(horizontal: false, vertical: true)

            PairedDotPlot(deltas: finding.pairDeltas, tint: tint)

            Text("\(finding.matchedPairCount) matched night\(finding.matchedPairCount == 1 ? "" : "s") · association, not proof of cause")
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open Cause Finder")
    }

    /// "Associated with 12% better deep sleep" -- the finding's own
    /// `headline`, reworded from "Tag: 12% better deep sleep" to a sentence.
    private func effectSentence(_ finding: JournalCorrelator.Finding) -> String {
        let direction = finding.isImprovement ? "better" : "worse"
        return "Associated with \(String(format: "%.0f%%", abs(finding.percentChange))) \(direction) \(finding.metric.shortLabel) on matched nights"
    }

    /// `JournalCorrelator.Confidence` has three levels to `MetricConfidence`'s
    /// four; there is no "insufficient" finding because one is never emitted.
    private static func metricConfidence(_ confidence: JournalCorrelator.Confidence) -> MetricConfidence {
        switch confidence {
        case .low: .low
        case .moderate: .moderate
        case .high: .high
        }
    }
}

private extension JournalCorrelator.Confidence {
    var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }
}

/// The running experiment as a trial ribbon rather than a progress row.
///
/// `GuidedExperiment.Status` exposes nights logged, not a per-day adherence
/// list, so the ribbon is honest about what it knows: one filled mark per
/// logged night toward the threshold, outlined marks for the rest, and the
/// result headline once the experiment has resolved. It never invents a
/// per-day tick or cross the data doesn't carry.
struct ExperimentPreview: View {
    let tag: BehaviorTag
    let status: GuidedExperiment.Status

    var body: some View {
        NavigationLink {
            CauseFinderView()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "flask.fill")
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(Theme.Family.sleep)
                    Text("Current experiment")
                        .font(Theme.kicker)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Text(tag.label)
                    .font(Theme.label(15, weight: .semibold))

                switch status {
                case let .learning(learning):
                    ribbon(filled: learning.loggedNights, total: JournalCorrelator.minimumMatchedPairs)
                    Text("Night \(learning.loggedNights) of about \(JournalCorrelator.minimumMatchedPairs) · \(learning.remainingNights) to go before a first read")
                        .font(Theme.evidence)
                        .foregroundStyle(.tertiary)
                case let .result(helpful, harmful):
                    if let strongest = (helpful + harmful).first {
                        Text(strongest.headline)
                            .font(Theme.text(14))
                            .fixedSize(horizontal: false, vertical: true)
                        PairedDotPlot(deltas: strongest.pairDeltas, tint: strongest.isImprovement ? Theme.Family.recovery : Theme.Family.attention)
                        ZoonEvidenceBadge(confidence: strongest.confidence == .high ? .high : strongest.confidence == .moderate ? .moderate : .low)
                    }
                case .noEffect:
                    Text("No meaningful difference found so far")
                        .font(Theme.text(14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func ribbon(filled: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Circle()
                    .strokeBorder(Theme.Family.sleep.opacity(0.5), lineWidth: 1.2)
                    .background(Circle().fill(index < filled ? Theme.Family.sleep : .clear))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) of \(total) nights logged")
    }
}

#Preview("Discoveries stream") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 32) {
                DiscoveriesStream(findings: AppMockData.correlationFindings, taggedNights: 20)
                DiscoveriesStream(findings: [], taggedNights: 3)
                ExperimentPreview(tag: .caffeineLate, status: .learning(.init(tag: .caffeineLate, loggedNights: 5)))
            }
            .padding()
        }
        .nightBackground()
    }
    .zoonPreviewEnvironment()
}

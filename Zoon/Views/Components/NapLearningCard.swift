import SwiftUI

/// What this person's own naps have sat alongside — never what they caused.
///
/// `NapLearning` shipped with tests and no caller. The engine already refuses
/// to say anything until six naps exist and phrases every finding as an
/// association; this is the surface that was missing, and it keeps that
/// framing rather than softening it into advice.
struct NapLearningCard: View {
    let findings: [NapLearning.Finding]

    var body: some View {
        if findings.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "What your naps have sat alongside",
                    subtitle: "Patterns in your own logs. Not cause and effect.",
                    systemImage: "sparkle.magnifyingglass"
                )

                ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(finding.sentence)
                            .font(Theme.text(13))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(finding.sampleCount) nap\(finding.sampleCount == 1 ? "" : "s") · \(finding.confidence.label)")
                            .font(Theme.evidence)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .glassCard()
        }
    }
}

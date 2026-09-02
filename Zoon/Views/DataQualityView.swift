import SwiftUI

/// Per-metric coverage over the trailing month, in one place -- see
/// `DataQuality`'s doc comment for why this exists as its own screen
/// rather than another footnote bolted onto an existing card.
struct DataQualityView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    private var quality: DataQuality {
        DataQuality.compute(nights: coordinator.recentNights)
    }

    var body: some View {
        ScrollView {
            // V8: the last week as a coverage matrix first -- one glance says
            // which signals were there -- then the 30-day percentages as
            // hairline-separated rows rather than a card each.
            VStack(alignment: .leading, spacing: 24) {
                header
                ZoonCoverageMatrix(nights: coordinator.recentNights)
                VStack(alignment: .leading, spacing: 10) {
                    ZoonSectionHeader("Last \(quality.windowDays) days")
                    VStack(spacing: 0) {
                        ForEach(Array(quality.coverage.enumerated()), id: \.element.id) { index, coverage in
                            if index > 0 { Rectangle().fill(Theme.cardStroke).frame(height: 1) }
                            row(coverage).padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Data Quality")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What Zoon has actually seen")
                .font(Theme.numeral(20))
            Text("""
                Coverage over the last \(quality.windowDays) days for every metric a score on this app \
                depends on. A gap here is the real reason a score's confidence is lower than usual -- \
                not a hidden fault.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ coverage: DataQuality.Coverage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: coverage.metric.symbol)
                    .font(Theme.text(13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(coverage.metric.label)
                    .font(Theme.label(13, weight: .medium))
                Spacer()
                // Text label alongside the percentage, not color alone --
                // "Limited"/"Insufficient" reads the same to someone who
                // can't distinguish the tint from "Reliable."
                Text("\(coverage.percent)% · \(coverage.confidence.label)")
                    .font(Theme.label(12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint(for: coverage.confidence))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.neutral(0.08))
                    Capsule()
                        .fill(tint(for: coverage.confidence))
                        .frame(width: geo.size.width * coverage.fraction)
                }
            }
            .frame(height: 5)
            Text("\(coverage.presentNightCount) of \(coverage.expectedNightCount) nights")
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coverage.metric.label): \(coverage.percent) percent, \(coverage.confidence.label), \(coverage.presentNightCount) of \(coverage.expectedNightCount) nights")
    }

    /// No red: a missing sensor is a fact about the hardware, not an alarm.
    /// The text label beside every percentage carries the meaning.
    private func tint(for confidence: DataQuality.Coverage.Confidence) -> Color {
        switch confidence {
        case .strong: Theme.Family.recovery
        case .limited: Theme.Family.attention
        case .insufficient: Theme.Family.deviation
        }
    }
}

#Preview("Data Quality") {
    NavigationStack {
        DataQualityView()
    }
    .zoonPreviewEnvironment()
}

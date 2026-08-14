import SwiftUI

/// Sleep Health, promoted from a row in Insights' hub list to the screen's
/// own hero -- the redesign spec's "INSIGHTS HERO: Sleep Health. Large: 88,
/// Thriving, +3 this month." The old hub simply listed it alongside every
/// other destination, which buried the one number the spec wants leading
/// the whole tab.
///
/// The trend line reuses `SleepHealth.compute` a second time with `now`
/// shifted back one window -- the same engine, not a new statistic invented
/// for the hero -- to compare this window's score against the one just
/// before it.
struct InsightsHero: View {
    @Environment(SleepDataCoordinator.self) private var coordinator
    let goalMinutes: Double

    private var feelings: [Int] {
        coordinator.journal.allEntries().compactMap(\.feeling).map(\.rawValue)
    }

    private var current: SleepHealth {
        SleepHealth.compute(
            window: .month, goalMinutes: goalMinutes,
            nights: coordinator.recentNights, morningFeelingRawValues: feelings
        )
    }

    private var previous: SleepHealth {
        let cutoff = Calendar.current.date(byAdding: .day, value: -SleepHealth.Window.month.rawValue, to: .now) ?? .distantPast
        return SleepHealth.compute(
            window: .month, goalMinutes: goalMinutes,
            nights: coordinator.recentNights, morningFeelingRawValues: feelings, now: cutoff
        )
    }

    private var trend: Int? {
        guard let currentScore = current.score, let previousScore = previous.score else { return nil }
        return Int((currentScore - previousScore).rounded())
    }

    var body: some View {
        NavigationLink {
            SleepHealthView()
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    ZoonIcon.SleepIntelligence(tint: Theme.Metric.sleep)
                        .frame(width: 13, height: 13)
                    Text("Sleep Health")
                        .font(Theme.label(13))
                        .foregroundStyle(.secondary)
                }

                if let score = current.score {
                    Text(String(format: "%.0f", score))
                        .font(Theme.numeral(46))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if let band = current.band {
                            StatusPill(text: band.label, tint: Theme.Metric.recoveryHigh)
                        }
                        if let trend, trend != 0 {
                            Label("\(trend > 0 ? "+" : "")\(trend) this month", systemImage: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(Theme.text(11, weight: .semibold))
                                .foregroundStyle(trend > 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid)
                        }
                    }
                } else {
                    Text("--")
                        .font(Theme.numeral(46))
                        .foregroundStyle(.tertiary)
                    StatusPill(text: "Insufficient data", tint: .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .glassCard()
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview("Insights Hero") {
    NavigationStack {
        InsightsHero(goalMinutes: 480)
            .padding()
            .nightBackground()
    }
    .zoonPreviewEnvironment()
}

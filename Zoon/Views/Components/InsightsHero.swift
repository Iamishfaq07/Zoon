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
    @Environment(UserPreferences.self) private var preferences
    let goalMinutes: Double

    /// The redesign spec's hero is scoped to one fixed window ("+3 this
    /// month"); this exposes the 14/30/90-day switch `SleepHealthView`
    /// itself already offers, since the hero previously had none at all.
    /// Kept outside the `NavigationLink` below rather than nested inside its
    /// label -- a `Picker` embedded in a `NavigationLink`'s label doesn't
    /// reliably get its own tap in SwiftUI, since the whole label is one tap
    /// target.
    @State private var window: SleepHealth.Window = .month

    /// Dated so `compute` can scope each call to its own window -- both
    /// calls below used to receive the exact same undated feelings array
    /// regardless of which period each was supposedly scoring.
    private var checkIns: [SleepHealth.DatedMorningCheckIn] {
        coordinator.journal.allEntries().map {
            SleepHealth.DatedMorningCheckIn(date: $0.date, feeling: $0.feeling?.rawValue)
        }
    }

    private var current: SleepHealth {
        SleepHealth.compute(
            window: window, goalMinutes: goalMinutes,
            nights: coordinator.recentNights, morningCheckIns: checkIns,
            obligationWeekdays: preferences.obligationWeekdays
        )
    }

    private var previous: SleepHealth {
        let cutoff = Calendar.current.date(byAdding: .day, value: -window.rawValue, to: .now) ?? .distantPast
        return SleepHealth.compute(
            window: window, goalMinutes: goalMinutes,
            nights: coordinator.recentNights, morningCheckIns: checkIns,
            obligationWeekdays: preferences.obligationWeekdays, now: cutoff
        )
    }

    private var trend: Int? {
        guard let currentScore = current.score, let previousScore = previous.score else { return nil }
        return Int((currentScore - previousScore).rounded())
    }

    var body: some View {
        VStack(spacing: 8) {
            windowPicker
            card
        }
    }

    private var windowPicker: some View {
        Picker("Window", selection: $window) {
            ForEach(SleepHealth.Window.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var card: some View {
        NavigationLink {
            SleepHealthView()
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    // 16, not 13: a detailed vector mark needs a little more
                    // room than the cap-height of the label beside it before
                    // its parts resolve. See ZoonIcon.SleepIntelligence.
                    ZoonIcon.SleepIntelligence(tint: Theme.Metric.sleep)
                        .frame(width: 16, height: 16)
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
                            Label("\(trend > 0 ? "+" : "")\(trend) vs prior \(window.label.lowercased())", systemImage: trend > 0 ? "arrow.up.right" : "arrow.down.right")
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

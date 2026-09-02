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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// V8: the hero sits on the page -- hero numeral, meaning word, trend --
    /// with the score change animating through `numericText` when the window
    /// picker moves. No card.
    private var card: some View {
        NavigationLink {
            SleepHealthView()
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 5) {
                    ZoonIcon.SleepIntelligence(tint: Theme.Family.sleep)
                        .frame(width: 16, height: 16)
                    Text("Sleep Health")
                        .font(Theme.kicker)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }

                if let score = current.score {
                    ZoonHeroMetric(
                        value: String(format: "%.0f", score),
                        meaning: current.band?.label ?? "",
                        tint: .primary
                    )
                    .animation(Motion.respecting(reduceMotion, Motion.value), value: window)

                    if let trend, trend != 0 {
                        Label("\(trend > 0 ? "+" : "")\(trend) vs prior \(window.label.lowercased())", systemImage: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(Theme.text(12, weight: .semibold))
                            .foregroundStyle(trend > 0 ? Theme.Family.recovery : Theme.Family.attention)
                            .contentTransition(.numericText())
                    } else {
                        Text("Steady vs prior \(window.label.lowercased())")
                            .font(Theme.text(12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    ZoonHeroMetric(value: "--", meaning: "Not enough nights yet", tint: .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open Sleep Health")
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

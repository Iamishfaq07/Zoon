import SwiftUI

/// Seven nights as moons filled by asleep vs need. Tap opens that night.
struct WeekMoonStrip: View {
    let nights: [SleepNightFeatures]
    let goalMinutes: Double
    @Binding var selected: SleepNightFeatures?

    private var week: [SleepNightFeatures] {
        Array(nights.suffix(7))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(week) { night in
                let fill = min(1, night.timeAsleepMinutes / max(goalMinutes, 1))
                let on = selected?.id == night.id
                Button {
                    Haptics.select()
                    selected = night
                } label: {
                    VStack(spacing: 6) {
                        MoonFill(fill: fill, active: on, size: 34)
                        Text(night.date, format: .dateTime.weekday(.narrow))
                            .font(Theme.text(11, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.primary : Theme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: night, fill: fill))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func accessibilityLabel(for night: SleepNightFeatures, fill: Double) -> String {
        let day = night.date.formatted(.dateTime.weekday(.wide))
        let percent = Int((fill * 100).rounded())
        return "\(day), \(night.formattedTimeAsleep) asleep, \(percent) percent of need"
    }
}

struct NightFilmStrip: View {
    let nights: [SleepNightFeatures]
    let goalMinutes: Double

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(nights) { night in
                    let fill = min(1, night.timeAsleepMinutes / max(goalMinutes, 1))
                    let met = night.timeAsleepMinutes >= goalMinutes
                    NavigationLink {
                        PastNightDetailView(night: night)
                    } label: {
                        VStack(alignment: .center, spacing: 8) {
                            MoonFill(fill: fill, active: met, size: 88)
                            Text(night.date, format: .dateTime.weekday(.abbreviated).day())
                                .font(Theme.text(11))
                                .foregroundStyle(Theme.inkSecondary)
                            Text(night.formattedTimeAsleep)
                                .font(Theme.label(13, weight: .semibold))
                                .monospacedDigit()
                        }
                        .frame(width: 88)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

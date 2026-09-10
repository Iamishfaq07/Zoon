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
                        MoonFill(fill: fill, active: on)
                        Text(night.date, format: .dateTime.weekday(.narrow))
                            .font(Theme.text(11, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
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
                    NavigationLink {
                        PastNightDetailView(night: night)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            MoonFill(
                                fill: min(1, night.timeAsleepMinutes / max(goalMinutes, 1)),
                                active: night.timeAsleepMinutes >= goalMinutes,
                                size: 56
                            )
                            Text(night.date, format: .dateTime.weekday(.abbreviated).day())
                                .font(Theme.text(11))
                                .foregroundStyle(.secondary)
                            Text(night.formattedTimeAsleep)
                                .font(Theme.label(13, weight: .semibold))
                                .monospacedDigit()
                        }
                        .frame(width: 76, alignment: .leading)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

struct MoonFill: View {
    var fill: Double
    var active: Bool
    var size: CGFloat = 28

    var body: some View {
        let clamped = min(1, max(0, fill))
        ZStack {
            Circle()
                .fill(Theme.Family.sleep.opacity(active ? 0.18 : 0))
            Circle()
                .stroke(Theme.cardStroke, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Theme.Family.sleep, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// Light Coach: time-anchored morning/evening light guidance. Renders
/// nothing outside either window -- a card with "nothing to do right now"
/// is worse than no card, and this one only has something to say twice a
/// day.
struct LightCoachCard: View {
    let guidance: LightCoach.Guidance

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: guidance.symbol)
                .foregroundStyle(Theme.Metric.battery)
                .frame(width: 24, height: 24)
                .background(Theme.Metric.battery.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(guidance.headline)
                    .font(Theme.label(14, weight: .semibold))
                Text(guidance.detail)
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .glassCard()
    }
}

#Preview("Light Coach") {
    VStack(spacing: 16) {
        LightCoachCard(guidance: LightCoach.Guidance(
            headline: "Get outside if you can",
            detail: "Bright light in the hour or so after waking is the strongest single cue for your body clock.",
            symbol: "sun.max"
        ))
        LightCoachCard(guidance: LightCoach.Guidance(
            headline: "Start dimming the lights",
            detail: "Bright light in the couple of hours before bed pushes your body clock later.",
            symbol: "moon.stars"
        ))
    }
    .padding()
    .nightBackground()
    .preferredColorScheme(.dark)
}

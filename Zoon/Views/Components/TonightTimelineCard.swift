import SwiftUI

/// Tonight, as a sequence of moments rather than one countdown number --
/// `BedtimeCountdownCard` already answers "how long until bedtime"; this
/// answers "what happens between now and morning." Same row-of-columns shape
/// `EnergyForecastCard` uses for the day ahead, applied to the night ahead.
///
/// All three times are read from data the app already computes elsewhere --
/// wind-down rides on `BedtimeReminder.windDownLeadMinutes`, the same lead
/// the actual notification uses, and wake comes from `BodyClock`'s own
/// window -- so this card can never show a different plan than the one the
/// reminders are actually scheduled against.
struct TonightTimelineCard: View {
    let windDown: Date
    let bedtime: Date
    /// `nil` before enough nights exist for `BodyClock` to estimate a wake
    /// window -- the card still shows wind-down and bedtime rather than
    /// disappearing entirely.
    let wake: Date?

    private struct Node: Identifiable {
        let id: String
        let symbol: String
        let label: String
        let time: Date
        let tint: Color
    }

    private var nodes: [Node] {
        var result = [
            Node(id: "windDown", symbol: "moon.haze.fill", label: "Wind down", time: windDown, tint: Theme.Metric.temperature),
            Node(id: "bedtime", symbol: "bed.double.fill", label: "Bedtime", time: bedtime, tint: Theme.Metric.sleep)
        ]
        if let wake {
            result.append(Node(id: "wake", symbol: "sunrise.fill", label: "Wake", time: wake, tint: Theme.Metric.battery))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tonight", systemImage: "moon.stars.fill")

            HStack(spacing: 0) {
                ForEach(nodes) { node in
                    VStack(spacing: 4) {
                        Image(systemName: node.symbol)
                            .font(Theme.text(15))
                            .foregroundStyle(node.tint)
                        Text(node.time, format: .dateTime.hour().minute())
                            .font(Theme.label(12, weight: .semibold))
                            .monospacedDigit()
                        Text(node.label)
                            .font(Theme.text(9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tonight's timeline")
    }
}

#Preview("Tonight Timeline") {
    ScrollView {
        TonightTimelineCard(
            windDown: Calendar.current.date(bySettingHour: 22, minute: 15, second: 0, of: .now) ?? .now,
            bedtime: Calendar.current.date(bySettingHour: 22, minute: 45, second: 0, of: .now) ?? .now,
            wake: Calendar.current.date(bySettingHour: 6, minute: 45, second: 0, of: .now.addingTimeInterval(86400)) ?? .now
        )
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}

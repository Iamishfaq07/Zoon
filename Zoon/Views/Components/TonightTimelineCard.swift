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
    /// General-guideline caffeine cutoff (`BedtimeReminder.caffeineCutoffLeadHours`
    /// before `bedtime`). `nil` hides the node entirely rather than showing a
    /// stale one -- the call site passes `nil` once the day's cutoff has
    /// already long passed and showing it would just read as clutter.
    let caffeineCutoff: Date?
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
        var result: [Node] = []
        if let caffeineCutoff {
            result.append(Node(id: "caffeine", symbol: "cup.and.saucer.fill", label: "Caffeine cutoff", time: caffeineCutoff, tint: Theme.Metric.strain))
        }
        result.append(contentsOf: [
            Node(id: "windDown", symbol: "moon.haze.fill", label: "Wind down", time: windDown, tint: Theme.Metric.temperature),
            Node(id: "bedtime", symbol: "bed.double.fill", label: "Bedtime", time: bedtime, tint: Theme.Metric.sleep)
        ])
        if let wake {
            result.append(Node(id: "wake", symbol: "sunrise.fill", label: "Wake", time: wake, tint: Theme.Metric.battery))
        }
        return result
    }

    /// How long after its own cutoff time today still shows it -- long enough
    /// to stay useful across an afternoon check-in, short enough that it's
    /// gone by evening rather than reading as stale clutter next to a
    /// bedtime that's actually approaching.
    private static let staleCaffeineCutoffToleranceHours = 3.0

    /// The general-guideline caffeine cutoff for a given target bedtime, or
    /// `nil` once it's far enough in the past that showing it would be
    /// clutter rather than guidance. Pure and `now`-parameterized so this is
    /// unit-testable without going through the view itself.
    static func caffeineCutoff(bedtime: Date, now: Date = .now) -> Date? {
        let cutoff = bedtime.addingTimeInterval(-BedtimeReminder.caffeineCutoffLeadHours * 3600)
        return cutoff > now.addingTimeInterval(-staleCaffeineCutoffToleranceHours * 3600) ? cutoff : nil
    }

    /// Height of the icon row above the time/label text -- the connecting
    /// line is centered on this, not the whole node column.
    private let iconRowHeight: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tonight", systemImage: "moon.stars.fill")

            ZStack(alignment: .top) {
                // A single connecting line reads as one sequence rather than
                // three unrelated columns; it only needs to span between the
                // first and last icon, so it's inset from the card's edges
                // by roughly half an icon's width on each side.
                Rectangle()
                    .fill(Theme.neutral(0.12))
                    .frame(height: 1.5)
                    .padding(.horizontal, 24)
                    .offset(y: iconRowHeight / 2)

                // A second, tinted line only under the portion that's
                // already happened -- the "past milestones visually
                // complete" state the timeline needs.
                if let progress = pastProgress {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.Metric.sleep.opacity(0.6))
                            .frame(width: max(0, geo.size.width - 48) * progress, height: 1.5)
                            .offset(x: 24, y: iconRowHeight / 2)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(nodes) { node in
                        let isPast = node.time <= .now
                        VStack(spacing: 4) {
                            Image(systemName: isPast ? "checkmark.circle.fill" : node.symbol)
                                .font(Theme.text(15))
                                .foregroundStyle(node.tint)
                                .opacity(isPast ? 0.6 : 1)
                                .frame(height: iconRowHeight)
                            Text(node.time, format: .dateTime.hour().minute())
                                .font(Theme.label(12, weight: .semibold))
                                .monospacedDigit()
                                .opacity(isPast ? 0.6 : 1)
                            Text(node.label)
                                .font(Theme.text(9))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tonight's timeline")
    }

    /// Fraction of the way from the first to the last node that "now" has
    /// reached, for the tinted portion of the connecting line. `nil` before
    /// wind-down, since nothing has started yet; `1` once wake has passed,
    /// so the whole line reads as complete.
    private var pastProgress: CGFloat? {
        guard let first = nodes.first?.time, let last = nodes.last?.time, last > first else { return nil }
        let now = Date.now
        guard now > first else { return nil }
        guard now < last else { return 1 }
        return CGFloat(now.timeIntervalSince(first) / last.timeIntervalSince(first))
    }
}

#Preview("Tonight Timeline") {
    ScrollView {
        TonightTimelineCard(
            caffeineCutoff: Calendar.current.date(bySettingHour: 14, minute: 45, second: 0, of: .now) ?? .now,
            windDown: Calendar.current.date(bySettingHour: 22, minute: 15, second: 0, of: .now) ?? .now,
            bedtime: Calendar.current.date(bySettingHour: 22, minute: 45, second: 0, of: .now) ?? .now,
            wake: Calendar.current.date(bySettingHour: 6, minute: 45, second: 0, of: .now.addingTimeInterval(86400)) ?? .now
        )
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}

#Preview("Tonight Timeline — no caffeine cutoff") {
    ScrollView {
        TonightTimelineCard(
            caffeineCutoff: nil,
            windDown: Calendar.current.date(bySettingHour: 22, minute: 15, second: 0, of: .now) ?? .now,
            bedtime: Calendar.current.date(bySettingHour: 22, minute: 45, second: 0, of: .now) ?? .now,
            wake: nil
        )
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}

import SwiftUI

/// What today's recovery actually means you should do.
///
/// Everything needed for this was already computed and shown separately:
/// the recovery band, and `EnergyForecast`'s named windows with real times.
/// What was missing is the sentence that joins them — Today said "67%,
/// Moderate" and left the reader to work out what to do about it.
///
/// Deliberately built only from those two, and phrased as a window rather
/// than an instruction. This is a sleep app reading physiology, not a coach
/// that knows your calendar: "your steadiest stretch is 4–5:30pm" is
/// something the data supports, "do 45 minutes of cardio then" is not.
struct TodayActionPlan: View {

    let recovery: RecoveryScore
    let forecast: EnergyForecast

    private var band: RecoveryScore.Band { recovery.band }

    /// The best window for effort: the day's highest named peak still ahead,
    /// falling back to the highest of the day once they have all passed.
    private var effortWindow: EnergyForecast.Window? {
        let peaks = forecast.windows.filter {
            $0.kind == .morningPeak || $0.kind == .eveningRise
        }
        return peaks.first { $0.time > .now } ?? peaks.last
    }

    private var dipWindow: EnergyForecast.Window? {
        forecast.windows.first { $0.kind == .afternoonDip }
    }

    private var headline: String {
        switch band {
        case .high: "A day your body can take load."
        case .moderate: "A moderate-output day."
        case .low: "A day to keep the load light."
        }
    }

    private var detail: String {
        var parts: [String] = []

        if let effortWindow {
            let range = forecast.timeRangeLabel(for: effortWindow)
            let verb = band == .low ? "Your steadiest stretch is" : "Your best window for effort is"
            parts.append("\(verb) \(range).")
        }

        if let dipWindow, dipWindow.time > .now {
            let time = dipWindow.time.formatted(.dateTime.hour().minute())
            parts.append("Expect a dip around \(time) — front-load anything demanding.")
        }

        if recovery.isEstimate {
            parts.append("Still building your baseline, so treat this as provisional.")
        }

        return parts.joined(separator: " ")
    }

    private var tint: Color {
        switch band {
        case .high: Theme.Family.recovery
        case .moderate: Theme.Family.attention
        case .low: Theme.Family.deviation
        }
    }

    var body: some View {
        if detail.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: band == .low ? "figure.mind.and.body" : "figure.run")
                    .font(Theme.text(20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your today's action plan")
                        .font(Theme.kicker)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSecondary)

                    Text(headline)
                        .font(Theme.label(15, weight: .semibold))

                    Text(detail)
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .glassCard(padding: 0)
            // An outline in the band's own colour, as in the mockup. The
            // card is the one thing on Today that asks you to *do*
            // something, and a tinted edge separates it from the readings
            // above and below without another fill competing with them.
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Your today's action plan. \(headline) \(detail)")
        }
    }
}

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

    /// Wake-side of the first window to past the last one.
    private var span: (start: Date, end: Date)? {
        guard let first = forecast.windows.map(\.time).min(),
              let last = forecast.windows.map(\.time).max(),
              last > first else { return nil }
        return (first.addingTimeInterval(-3600), last.addingTimeInterval(3600))
    }

    @ViewBuilder
    private var dayStrip: some View {
        if let span {
            let total = span.end.timeIntervalSince(span.start)
            let position: (Date) -> Double = { min(1, max(0, $0.timeIntervalSince(span.start) / total)) }
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.neutral(0.10)).frame(height: 8)
                        if let effortWindow {
                            let start = position(effortWindow.time.addingTimeInterval(-45 * 60))
                            let end = position(effortWindow.time.addingTimeInterval(45 * 60))
                            Capsule()
                                .fill(tint)
                                .frame(width: max(8, (end - start) * width), height: 8)
                                .offset(x: start * width)
                        }
                        if let dipWindow {
                            Circle()
                                .fill(Theme.Metric.recoveryMid)
                                .frame(width: 10, height: 10)
                                .offset(x: position(dipWindow.time) * width - 5)
                        }
                        Rectangle()
                            .fill(Theme.ink)
                            .frame(width: 2, height: 16)
                            .offset(x: position(.now) * width - 1)
                    }
                    .frame(height: 16)
                }
                .frame(height: 16)
                HStack(spacing: 12) {
                    if let effortWindow {
                        Label(forecast.timeRangeLabel(for: effortWindow), systemImage: band == .low ? "leaf.fill" : "bolt.fill")
                            .foregroundStyle(tint)
                    }
                    if let dipWindow, dipWindow.time > .now {
                        Label("Dip \(dipWindow.time.formatted(.dateTime.hour().minute()))", systemImage: "cloud.sun.fill")
                            .foregroundStyle(Theme.Metric.recoveryMid)
                    }
                }
                .font(Theme.text(11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        } else {
            Text(detail)
                .font(Theme.text(13))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tint: Color {
        switch band {
        case .high: Theme.Family.recovery
        case .moderate: Theme.Family.attention
        case .low: Theme.Family.deviation
        }
    }

    var body: some View {
        // A plan is advice derived from the band, and the band is the score.
        // When the score cannot be stated the advice cannot either; the
        // energy windows below remain available on their own screen.
        if !recovery.presentation.isShowable || detail.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: band == .low ? "figure.mind.and.body" : "figure.run")
                    .font(Theme.text(20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your plan for today")
                        .font(Theme.kicker)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSecondary)

                    Text(headline)
                        .font(Theme.label(15, weight: .semibold))

                    // The day as a strip rather than two sentences of
                    // times: the best stretch lit, the dip marked, now as a
                    // dot. The sentence is still the VoiceOver label.
                    dayStrip
                        .padding(.top, 6)
                    if recovery.isEstimate {
                        Text("Provisional while your baseline builds.")
                            .font(Theme.evidence)
                            .foregroundStyle(Theme.inkTertiary)
                    }
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
            .accessibilityLabel("Your plan for today. \(headline) \(detail)")
        }
    }
}

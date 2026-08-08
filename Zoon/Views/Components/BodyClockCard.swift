import SwiftUI

/// The circadian window, drawn as a 24-hour dial.
///
/// A dial rather than a bar because the quantity is genuinely circular — the
/// window usually straddles midnight, and every linear layout has to either cut
/// it in half or renumber the axis. On a clock face it is simply an arc.
struct BodyClockCard: View {

    let bodyClock: BodyClock
    /// Tonight's plan, so the card can show the gap between intention and rhythm.
    var plannedBedtime: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: Double = 0

    private var driftMinutes: Double? {
        plannedBedtime.flatMap { bodyClock.drift(of: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Body Clock", systemImage: "circle.dotted")

            HStack(alignment: .center, spacing: 18) {
                dial
                    .frame(width: 116, height: 116)

                VStack(alignment: .leading, spacing: 8) {
                    windowRow
                    Divider().overlay(Theme.cardStroke)
                    stabilityRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if bodyClock.isEstimate {
                Text("Estimated from \(bodyClock.nightCount) night\(bodyClock.nightCount == 1 ? "" : "s"). Firms up after \(BodyClock.minimumNights).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let drift = driftMinutes, abs(drift) >= 30 {
                driftNote(drift)
            } else {
                Text("This is when your body has been choosing to sleep — not a target, an observation.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
        .onAppear {
            guard !reduceMotion else { sweep = 1; return }
            withAnimation(.easeOut(duration: 0.9)) { sweep = 1 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Body clock")
        .accessibilityValue(
            "Usual sleep window \(BodyClock.formatted(hour: bodyClock.onsetHour)) "
            + "to \(BodyClock.formatted(hour: bodyClock.wakeHour)). "
            + "Stability \(bodyClock.stability.label)."
        )
    }

    // MARK: - Dial

    private var dial: some View {
        ZStack {
            // Hour ticks. Midnight at the top, noon at the bottom — the
            // orientation of an actual 24-hour clock, and it puts the sleep
            // window where people expect to see night.
            ForEach(0..<24, id: \.self) { hour in
                let major = hour % 6 == 0
                Capsule()
                    .fill(Color.white.opacity(major ? 0.30 : 0.12))
                    .frame(width: major ? 2 : 1, height: major ? 8 : 5)
                    .offset(y: -52)
                    .rotationEffect(.degrees(Double(hour) / 24 * 360))
            }

            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 10)
                .frame(width: 92, height: 92)

            // The window itself.
            Circle()
                .trim(from: 0, to: max(0, min(1, arcLength * sweep)))
                .stroke(
                    AngularGradient(
                        colors: [Theme.Metric.sleep, Theme.Metric.battery, Theme.Metric.sleep],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: 92, height: 92)
                // -90 puts trim's 3-o'clock origin at the top, then the window's
                // own start angle rotates it into place.
                .rotationEffect(.degrees(-90 + arcStart * 360))
                .shadow(color: Theme.Metric.sleep.opacity(0.5), radius: 8)

            VStack(spacing: 0) {
                Text("MID")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(BodyClock.formatted(hour: bodyClock.midpoint))
                    .font(Theme.numeral(15))
                    .monospacedDigit()
            }
        }
    }

    /// Window start as a fraction of the 24-hour dial.
    private var arcStart: Double {
        var hour = bodyClock.onsetHour
        if hour < 0 { hour += 24 }
        return hour / 24
    }

    private var arcLength: Double {
        (bodyClock.typicalDurationMinutes / 60) / 24
    }

    // MARK: - Rows

    private var windowRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Your window")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(BodyClock.formatted(hour: bodyClock.onsetHour))
                    .font(Theme.numeral(19))
                    .foregroundStyle(Theme.Metric.sleep)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(BodyClock.formatted(hour: bodyClock.wakeHour))
                    .font(Theme.numeral(19))
                    .foregroundStyle(Theme.Metric.battery)
            }
            .monospacedDigit()
        }
    }

    private var stabilityRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Stability")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                StatusPill(
                    text: bodyClock.stability.label,
                    systemImage: stabilitySymbol,
                    tint: stabilityTint
                )
            }
            Text(bodyClock.stability.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func driftNote(_ drift: Double) -> some View {
        let late = drift > 0
        let magnitude = SleepNightFeatures.formatMinutes(abs(drift))
        return Label(
            late
            ? "Tonight's bedtime is \(magnitude) later than your body's usual window."
            : "Tonight's bedtime is \(magnitude) earlier than your body's usual window.",
            systemImage: late ? "arrow.right.circle" : "arrow.left.circle"
        )
        .font(.caption2)
        .foregroundStyle(Theme.Metric.recoveryMid)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var stabilitySymbol: String {
        switch bodyClock.stability {
        case .tight: "target"
        case .typical: "circle.dashed"
        case .scattered: "scribble"
        }
    }

    private var stabilityTint: Color {
        switch bodyClock.stability {
        case .tight: Theme.Metric.recoveryHigh
        case .typical: Theme.Metric.sleep
        case .scattered: Theme.Metric.recoveryMid
        }
    }
}

#Preview("Body Clock") {
    ScrollView {
        VStack(spacing: Theme.stackSpacing) {
            if let clock = BodyClock.compute(nights: MockData.history) {
                BodyClockCard(
                    bodyClock: clock,
                    plannedBedtime: Calendar.current.date(
                        bySettingHour: 1, minute: 15, second: 0, of: .now
                    )
                )
                BodyClockCard(bodyClock: clock)
            }
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}

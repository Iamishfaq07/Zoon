import SwiftUI

/// Sleep timing regularity, social jetlag, and the consistency dial.
///
/// Given prominence on purpose. Duration is the number every app optimises;
/// regularity is the one the evidence favours and almost nobody surfaces, so
/// it gets a real card rather than a footnote.
struct RegularityCard: View {

    let regularity: SleepRegularity

    @State private var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        switch regularity.band {
        case .exemplary: Theme.Metric.recoveryHigh
        case .consistent: Theme.Metric.battery
        case .variable: Theme.Metric.recoveryMid
        case .erratic: Theme.Metric.recoveryLow
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: "Sleep Regularity",
                    subtitle: "How reliably you're asleep at the same clock times.",
                    systemImage: "repeat"
                )
                Spacer(minLength: 8)
                MetricInfoButton(
                    title: "Sleep Regularity",
                    symbol: "repeat",
                    tint: tint,
                    explanation: [
                        "Measures how consistent your sleep and wake times are night to night, on a 0-100 scale -- it's about rhythm, not duration. This approximates the academic Sleep Regularity Index but only samples the hours around your actual sleep, not a full 24-hour day, so it isn't presented as that exact metric.",
                        "Social jetlag is the gap between your work-day and free-day sleep midpoints. A large gap behaves physiologically a lot like crossing time zones, even without travelling."
                    ],
                    relatedArticleID: "sleep-consistency"
                )
                if regularity.hasEnoughData {
                    StatusPill(text: regularity.band.label, tint: tint)
                }
            }

            if regularity.hasEnoughData {
                HStack(spacing: 16) {
                    dial
                    VStack(alignment: .leading, spacing: 8) {
                        if let jetlag = regularity.socialJetlagHours {
                            stat(
                                String(format: "%.1fh", jetlag),
                                "social jetlag",
                                jetlag < 1 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid
                            )
                        }
                        if let weekday = regularity.weekdayMidpoint {
                            stat(clock(weekday), "work-day midpoint", Theme.Metric.sleep)
                        }
                        if let weekend = regularity.weekendMidpoint {
                            stat(clock(weekend), "free-day midpoint", Theme.Metric.strain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text(regularity.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let jetlagDetail = regularity.socialJetlagDetail {
                Divider().overlay(Theme.cardStroke)
                Label {
                    Text(jetlagDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "airplane")
                        .font(.caption2)
                        .foregroundStyle(Theme.Metric.strain)
                }
            }
        }
        .glassCard()
        .onAppear {
            if reduceMotion { animated = true }
            else { withAnimation(Motion.hero) { animated = true } }
        }
    }

    private var dial: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.neutral(0.08), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            Circle()
                .trim(from: 0, to: animated ? 0.75 * (regularity.index / 100) : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
        }
        // Rotated so the 3/4 arc opens at the bottom, like a gauge. The label
        // sits in an overlay outside the rotation so it stays upright.
        .rotationEffect(.degrees(135))
        .frame(width: 84, height: 84)
        .overlay {
            VStack(spacing: -2) {
                Text("\(Int(regularity.index.rounded()))")
                    .font(Theme.numeral(24))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text("TIMING")
                    .font(Theme.text(8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep timing regularity")
        .accessibilityValue("\(Int(regularity.index)) out of 100, \(regularity.band.label)")
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(value)
                .font(Theme.label(14, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
        }
    }

    /// Shifted hours back to a clock string.
    private func clock(_ shiftedHour: Double) -> String {
        let hour = shiftedHour < 0 ? shiftedHour + 24 : shiftedHour
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        return String(format: "%02d:%02d", h % 24, abs(m))
    }
}

/// Oura-style multi-night drift detection.
///
/// Renders nothing at all when there's nothing to report — a card that
/// permanently says "all clear" trains people to stop reading it, and then it's
/// invisible on the day it finally matters.
struct HealthRadarCard: View {

    let radar: HealthRadar

    private var tint: Color {
        switch radar.severity {
        case .clear: Theme.Metric.recoveryHigh
        case .watch: Theme.Metric.recoveryMid
        case .notable: Theme.Metric.recoveryLow
        }
    }

    var body: some View {
        if radar.isActive {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // Explicit "illness risk" wording rather than a second,
                    // separately-computed score: the detection underneath is
                    // already the thing competitors call illness prediction —
                    // several vitals drifting together, sustained for days.
                    // Naming it plainly here is cheaper and more honest than
                    // building a second model that would just restate this one.
                    SectionHeader(
                        title: "Body Signals",
                        subtitle: radar.severity == .notable ? "Possible illness or heavy strain signal" : nil,
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    Spacer()
                    MetricInfoButton(
                        title: "Body Signals",
                        symbol: "dot.radiowaves.left.and.right",
                        tint: tint,
                        explanation: [
                            "Watches several vitals at once -- resting heart rate, HRV, respiratory rate, wrist temperature -- for a sustained drift together over multiple nights, which is a stronger signal than any one of them moving alone.",
                            "This is a wellness observation, not a diagnosis. It cannot identify illness, only flag a pattern worth paying attention to."
                        ]
                    )
                    StatusPill(text: radar.severity.label, tint: tint)
                }

                ForEach(radar.signals) { signal in
                    HStack(spacing: 10) {
                        Image(systemName: signal.kind.symbol)
                            .font(Theme.text(12))
                            .foregroundStyle(tint)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(signal.kind.label)
                                .font(Theme.label(12, weight: .medium))
                            Text("\(signal.consecutiveNights) nights \(signal.direction == .elevated ? "elevated" : "below baseline")")
                                .font(Theme.text(10))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: signal.direction.symbol)
                                .font(Theme.text(10, weight: .bold))
                            Text(String(format: "%+.0f%%", signal.percentChange))
                                .font(Theme.label(12, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(tint)
                    }
                }

                Text(radar.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(SleepInsight.disclaimer)
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard()
        }
    }
}

/// Cardiovascular age.
struct CardiovascularAgeCard: View {

    let cvAge: CardiovascularAge

    private var tint: Color {
        switch cvAge.standing {
        case .younger: Theme.Metric.recoveryHigh
        case .aligned: Theme.Metric.battery
        case .older: Theme.Metric.recoveryMid
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                SectionHeader(title: "Cardiovascular Age", systemImage: "heart.circle")
                Spacer(minLength: 8)
                // A tertiary-colored disclaimer at the bottom of the card is
                // easy to skim past on a number this large and this
                // confident-looking. This sits right next to the title
                // instead, where it's read first.
                StatusPill(text: "Experimental", tint: .secondary)
                MetricInfoButton(
                    title: "Cardiovascular Age",
                    symbol: "heart.circle",
                    tint: tint,
                    explanation: [
                        "An estimate derived from your resting heart rate and HRV relative to population norms for your age -- not a clinical or lab-based measurement, and not validated against any reference standard.",
                        "Treat the direction (younger, aligned, older than your actual age) as more meaningful than the exact number, which will vary night to night."
                    ]
                )
            }

            HStack(alignment: .center, spacing: 18) {
                VStack(spacing: -2) {
                    Text(cvAge.displayAge)
                        .font(Theme.numeral(46))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Text("estimated")
                        .font(Theme.text(10))
                        .foregroundStyle(.tertiary)
                }

                // A short axis showing where the estimate sits relative to
                // actual age — the comparison is the whole point, and two bare
                // numbers side by side don't communicate it.
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        let span = 20.0
                        let position = (cvAge.deltaYears + span / 2) / span
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.neutral(0.08))
                            Capsule()
                                .fill(Theme.Metric.battery.opacity(0.3))
                                .frame(width: geo.size.width * 0.5)
                                .offset(x: geo.size.width * 0.25)
                            Circle()
                                .fill(tint)
                                .frame(width: 10, height: 10)
                                .shadow(color: tint.opacity(0.8), radius: 5)
                                .offset(x: geo.size.width * min(max(position, 0), 1) - 5)
                        }
                    }
                    .frame(height: 10)

                    HStack {
                        Text("−10y").font(Theme.text(9)).foregroundStyle(.tertiary)
                        Spacer()
                        Text("age \(cvAge.chronologicalAge)").font(Theme.text(9)).foregroundStyle(.secondary)
                        Spacer()
                        Text("+10y").font(Theme.text(9)).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Text(cvAge.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(CardiovascularAge.disclaimer)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cardiovascular age")
        .accessibilityValue("\(cvAge.displayAge), \(cvAge.standing.label)")
    }
}

#Preview("New cards") {
    let context = AppMockData.dayContext()
    return ScrollView {
        VStack(spacing: 16) {
            RegularityCard(regularity: context.regularity)
            if let cv = context.cardiovascularAge {
                CardiovascularAgeCard(cvAge: cv)
            }
            HealthRadarCard(radar: AppMockData.activeRadar)
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}

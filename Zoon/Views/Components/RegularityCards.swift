import SwiftUI

/// Sleep Regularity Index, social jetlag, and the consistency dial.
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
            else { withAnimation(.spring(response: 1.0, dampingFraction: 0.82)) { animated = true } }
        }
    }

    private var dial: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 9, lineCap: .round))
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
                Text("SRI")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep regularity index")
        .accessibilityValue("\(Int(regularity.index)) out of 100, \(regularity.band.label)")
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(value)
                .font(Theme.label(14, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
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
                    SectionHeader(title: "Health Radar", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    StatusPill(text: radar.severity.label, tint: tint)
                }

                ForEach(radar.signals) { signal in
                    HStack(spacing: 10) {
                        Image(systemName: signal.kind.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(tint)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(signal.kind.label)
                                .font(Theme.label(12, weight: .medium))
                            Text("\(signal.consecutiveNights) nights \(signal.direction == .elevated ? "elevated" : "below baseline")")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: signal.direction.symbol)
                                .font(.system(size: 10, weight: .bold))
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
                    .font(.system(size: 10))
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
            SectionHeader(title: "Cardiovascular Age", systemImage: "heart.circle")

            HStack(alignment: .center, spacing: 18) {
                VStack(spacing: -2) {
                    Text(cvAge.displayAge)
                        .font(Theme.numeral(46))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Text("estimated")
                        .font(.system(size: 10))
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
                            Capsule().fill(Color.white.opacity(0.08))
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
                        Text("−10y").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Spacer()
                        Text("age \(cvAge.chronologicalAge)").font(.system(size: 9)).foregroundStyle(.secondary)
                        Spacer()
                        Text("+10y").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Text(cvAge.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(CardiovascularAge.disclaimer)
                .font(.system(size: 10))
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

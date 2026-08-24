import SwiftUI

/// The signature 24-hour circadian visualization — your estimated preferred
/// sleep window laid against what actually happened last night, on one ring.
struct BodyClockView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    /// Set only when pushed from `CoreIntelligenceGrid`'s tile -- see
    /// `SleepNeedView`'s doc comment on the same pair of properties.
    var zoomNamespace: Namespace.ID? = nil
    var zoomID: String? = nil

    private var bodyClock: BodyClock? { coordinator.state.context?.bodyClock }
    private var night: SleepNightFeatures? { coordinator.state.context?.night }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let bodyClock, let night {
                    ring(bodyClock: bodyClock, night: night)
                    alignmentCard(bodyClock: bodyClock, night: night)
                    stabilityCard(bodyClock)
                    explanationCard
                } else {
                    ContentUnavailableView(
                        "Building your body clock",
                        systemImage: "clock",
                        description: Text("Zoon needs \(BodyClock.minimumNights) nights of history before it can estimate your preferred sleep window.")
                    )
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Body Clock")
        .navigationBarTitleDisplayMode(.inline)
        .navigationTransition(zoomNamespace == nil ? .automatic : .zoom(sourceID: zoomID ?? "", in: zoomNamespace!))
    }

    // MARK: - Ring

    private func ring(bodyClock: BodyClock, night: SleepNightFeatures) -> some View {
        let onset = wallClockFraction(bodyClock.onsetHour)
        let wake = wallClockFraction(bodyClock.wakeHour)
        let actualStart = wallClockFraction(hourOfDay(night.bedtime))
        let actualEnd = wallClockFraction(hourOfDay(night.wakeTime))

        return VStack(spacing: 14) {
            ZStack {
                // Hour ticks, four per side, unlabeled dial marks.
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(Theme.neutral(hour % 6 == 0 ? 0.25 : 0.08))
                        .frame(width: hour % 6 == 0 ? 2 : 1, height: hour % 6 == 0 ? 10 : 5)
                        .offset(y: -108)
                        .rotationEffect(.degrees(Double(hour) / 24 * 360))
                }

                // Estimated preferred window.
                arc(from: onset, to: wake, lineWidth: 16)
                    .fill(Theme.Metric.sleep.opacity(0.35))

                // Actual sleep.
                arc(from: actualStart, to: actualEnd, lineWidth: 16)
                    .stroke(Theme.Metric.battery, style: StrokeStyle(lineWidth: 4, lineCap: .round))

                // Where "now" sits on the dial -- the live position against
                // the fixed shape of the day, same marker as the Body Clock
                // card on the Sleep tab.
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .white.opacity(0.7), radius: 4)
                    .offset(y: -100)
                    .rotationEffect(.degrees(wallClockFraction(hourOfDay(.now)) * 360))

                VStack(spacing: 2) {
                    Text(BodyClock.formatted(hour: bodyClock.onsetHour))
                        .font(Theme.label(15, weight: .bold))
                    Text("to")
                        .font(Theme.text(9))
                        .foregroundStyle(.tertiary)
                    Text(BodyClock.formatted(hour: bodyClock.wakeHour))
                        .font(Theme.label(15, weight: .bold))
                    Text("estimated window")
                        .font(Theme.text(9))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .frame(width: 240, height: 240)

            HStack(spacing: 16) {
                legend(color: Theme.Metric.sleep, label: "Estimated window")
                legend(color: Theme.Metric.battery, label: "Actual sleep")
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(Theme.text(10)).foregroundStyle(.secondary)
        }
    }

    /// An arc shape between two 0...1 fractions of the 24-hour circle,
    /// starting at the top (midnight) and running clockwise.
    private func arc(from start: Double, to end: Double, lineWidth: CGFloat) -> Path {
        var path = Path()
        let radius: CGFloat = 100
        let center = CGPoint(x: 120, y: 120)
        let startAngle = Angle(degrees: start * 360 - 90)
        var endAngle = Angle(degrees: end * 360 - 90)
        if endAngle.degrees <= startAngle.degrees { endAngle.degrees += 360 }
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }

    // MARK: - Alignment

    private func alignmentCard(bodyClock: BodyClock, night: SleepNightFeatures) -> some View {
        let driftMinutes = bodyClock.drift(of: night.bedtime) ?? 0
        let alignment = alignmentScore(driftMinutes: driftMinutes)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Circadian Alignment", systemImage: "target")
                Spacer()
                Text("\(Int(alignment))/100")
                    .font(Theme.numeral(20))
                    .monospacedDigit()
                    .foregroundStyle(Theme.recoveryColor(alignment))
            }
            Text(alignmentSentence(driftMinutes: driftMinutes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func alignmentScore(driftMinutes: Double) -> Double {
        Statistics.interpolate(abs(driftMinutes), anchors: [
            (0, 100), (15, 100), (30, 90), (60, 75), (90, 55), (120, 35), (180, 10), (240, 0)
        ])
    }

    private func alignmentSentence(driftMinutes: Double) -> String {
        guard abs(driftMinutes) >= 10 else {
            return "Your sleep started right around your usual preferred timing."
        }
        let direction = driftMinutes > 0 ? "later" : "earlier"
        return "Your sleep started about \(Int(abs(driftMinutes))) minutes \(direction) than your recent preferred timing."
    }

    // MARK: - Stability

    private func stabilityCard(_ bodyClock: BodyClock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Rhythm Stability", systemImage: "waveform.path")
                Spacer()
                StatusPill(text: bodyClock.stability.label, tint: stabilityTint(bodyClock.stability))
            }
            Text(bodyClock.stability.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func stabilityTint(_ stability: BodyClock.Stability) -> Color {
        switch stability {
        case .tight: Theme.Metric.recoveryHigh
        case .typical: Theme.Metric.battery
        case .scattered: Theme.Metric.recoveryMid
        }
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How is this estimated?", systemImage: "info.circle")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("""
                Estimated body clock, not a direct measurement -- nothing on a wrist measures \
                circadian phase. This is built from your recent sleep midpoint, bedtime, wake \
                time, and regularity, averaged as clock positions rather than plain numbers so a \
                night crossing midnight doesn't distort the result.
                """)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    // MARK: - Helpers

    private func hourOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    /// Converts an hours-from-midnight value (possibly negative, evening
    /// convention) to a 0...1 fraction of the 24-hour wall-clock dial.
    private func wallClockFraction(_ hour: Double) -> Double {
        var h = hour
        while h < 0 { h += 24 }
        while h >= 24 { h -= 24 }
        return h / 24
    }
}

#Preview("Body Clock") {
    NavigationStack { BodyClockView() }
        .zoonPreviewEnvironment()
}

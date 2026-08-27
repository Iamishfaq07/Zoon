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
        // `.zoom(...)` and `.automatic` are different concrete types
        // conforming to `NavigationTransition`, so branching the transition
        // value itself (e.g. via a ternary) doesn't type-check -- branching
        // the view instead lets each branch's `.navigationTransition(_:)`
        // call resolve its own concrete opaque type independently.
        if let zoomNamespace, let zoomID {
            content.navigationTransition(.zoom(sourceID: zoomID, in: zoomNamespace))
        } else {
            content.navigationTransition(.automatic)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let bodyClock, let night {
                    ring(bodyClock: bodyClock, night: night)
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
    }

    // MARK: - Ring

    /// One drag-to-inspect finger position, as a 0...1 fraction of the
    /// 24-hour dial -- `nil` when nothing is currently touched, which is
    /// when the ring shows the alignment score instead.
    @State private var inspectedFraction: Double?

    private func ring(bodyClock: BodyClock, night: SleepNightFeatures) -> some View {
        let onset = wallClockFraction(bodyClock.onsetHour)
        let wake = wallClockFraction(bodyClock.wakeHour)
        let actualStart = wallClockFraction(hourOfDay(night.bedtime))
        let actualEnd = wallClockFraction(hourOfDay(night.wakeTime))
        let driftMinutes = bodyClock.drift(of: night.bedtime) ?? 0
        let alignment = alignmentScore(driftMinutes: driftMinutes)
        let forecast = EnergyForecast.compute(
            wakeTime: night.wakeTime,
            sleepDebtMinutes: night.sleepDebtMinutes ?? 0,
            windDownHour: bodyClock.isEstimate ? nil : bodyClock.onsetHour
        )
        // Peak, dip, and wind-down only -- the redesign spec's three named
        // layers. Morning rise and second wind sit close enough to the
        // window edges already on screen that marking them too would just
        // be visual noise around the same arc.
        let energyMarks = forecast.windows.filter {
            $0.kind == .morningPeak || $0.kind == .afternoonDip || $0.kind == .windDown
        }
        let markers = inspectionMarkers(
            onset: onset, wake: wake, actualStart: actualStart, actualEnd: actualEnd,
            energyMarks: energyMarks
        )

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

                // Energy Horizon's peak/dip/wind-down carried onto the same
                // dial, at the same wall-clock fractions `EnergyForecastCard`
                // draws its curve from -- the two screens describe the same
                // day, so their markers land at the same angle here.
                ForEach(energyMarks) { mark in
                    energyMarker(mark)
                }

                // Where "now" sits on the dial -- the live position against
                // the fixed shape of the day, same marker as the Body Clock
                // card on the Sleep tab.
                Circle()
                    .fill(Theme.dialMarker)
                    .frame(width: 8, height: 8)
                    .shadow(color: Theme.dialMarker.opacity(0.7), radius: 4)
                    .offset(y: -100)
                    .rotationEffect(.degrees(wallClockFraction(hourOfDay(.now)) * 360))

                centerContent(
                    alignment: alignment,
                    inspected: inspectedFraction.map { fraction in nearestMarker(to: fraction, in: markers) }
                )
            }
            .frame(width: 240, height: 240)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        inspectedFraction = dialFraction(for: value.location, in: CGSize(width: 240, height: 240))
                    }
                    .onEnded { _ in inspectedFraction = nil }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Body clock dial")
            .accessibilityValue(
                "Estimated window \(BodyClock.formatted(hour: bodyClock.onsetHour)) to "
                + "\(BodyClock.formatted(hour: bodyClock.wakeHour)). Actual sleep "
                + "\(BodyClock.formatted(hour: hourOfDay(night.bedtime))) to "
                + "\(BodyClock.formatted(hour: hourOfDay(night.wakeTime))). "
                + "Circadian alignment \(Int(alignment)) out of 100."
            )

            HStack(spacing: 14) {
                legend(color: Theme.Metric.sleep, label: "Estimated window")
                legend(color: Theme.Metric.battery, label: "Actual sleep")
                legend(color: Theme.Metric.battery.opacity(0.7), label: "Energy")
            }

            Text(alignmentSentence(driftMinutes: driftMinutes))
                .font(Theme.text(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    /// A small dot and symbol for one Energy Horizon window, positioned on
    /// the dial's outer edge at that window's wall-clock time.
    private func energyMarker(_ window: EnergyForecast.Window) -> some View {
        let fraction = wallClockFraction(hourOfDay(window.time))
        return Image(systemName: window.kind.symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.Metric.battery.opacity(0.85))
            .frame(width: 16, height: 16)
            .background(Theme.background.opacity(0.9), in: Circle())
            .offset(y: -108)
            .rotationEffect(.degrees(fraction * 360))
    }

    /// One point-of-interest on the dial, for drag-to-inspect to snap to and
    /// label -- window edges and Energy Horizon marks, not the live "now"
    /// dot, which needs no explanation once you're already touching it.
    private struct InspectionMarker {
        let fraction: Double
        let label: String
    }

    private func inspectionMarkers(
        onset: Double, wake: Double, actualStart: Double, actualEnd: Double,
        energyMarks: [EnergyForecast.Window]
    ) -> [InspectionMarker] {
        var markers = [
            InspectionMarker(fraction: onset, label: "Window starts"),
            InspectionMarker(fraction: wake, label: "Window ends"),
            InspectionMarker(fraction: actualStart, label: "Fell asleep"),
            InspectionMarker(fraction: actualEnd, label: "Woke up")
        ]
        markers += energyMarks.map {
            InspectionMarker(fraction: wallClockFraction(hourOfDay($0.time)), label: $0.kind.label)
        }
        return markers
    }

    /// The marker nearest a drag position, if it's close enough to count as
    /// "pointing at" it (within 24 minutes either way) -- otherwise `nil`,
    /// which leaves the center showing the plain time under the finger.
    private func nearestMarker(to fraction: Double, in markers: [InspectionMarker]) -> String? {
        let threshold = 0.017 // ~24 minutes of the 24-hour dial
        let nearest = markers.min { lhs, rhs in
            circularDistance(fraction, lhs.fraction) < circularDistance(fraction, rhs.fraction)
        }
        guard let nearest, circularDistance(fraction, nearest.fraction) <= threshold else { return nil }
        return nearest.label
    }

    private func circularDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(diff, 1 - diff)
    }

    /// A drag location within the ring's own frame, converted to a 0...1
    /// wall-clock fraction on the same midnight-at-top, clockwise
    /// convention the tick marks and arcs use.
    private func dialFraction(for location: CGPoint, in size: CGSize) -> Double {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees / 360
    }

    @ViewBuilder
    private func centerContent(alignment: Double, inspected: String??) -> some View {
        if let inspected {
            // `inspected` is `String??`: outer optional is "not touching the
            // dial", inner is "touching it, but not near a named marker".
            VStack(spacing: 2) {
                if let label = inspected {
                    Text(label)
                        .font(Theme.label(13, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(BodyClock.formatted(hour: hourOfDay(inspectedTime ?? .now)))
                        .font(Theme.numeral(19))
                }
            }
            .padding(.horizontal, 8)
        } else {
            VStack(spacing: 2) {
                Text("\(Int(alignment))")
                    .font(Theme.numeral(32))
                    .monospacedDigit()
                    .foregroundStyle(Theme.recoveryColor(alignment))
                Text("alignment")
                    .font(Theme.text(9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// The wall-clock time the current drag position corresponds to, for the
    /// center label when the finger isn't near a named marker. Recomputed
    /// from `inspectedFraction` rather than carried as a second `@State`,
    /// since the fraction is already the source of truth.
    private var inspectedTime: Date? {
        guard let inspectedFraction else { return nil }
        let hours = inspectedFraction * 24
        return Calendar.current.startOfDay(for: .now).addingTimeInterval(hours * 3600)
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
                .font(Theme.text(12))
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

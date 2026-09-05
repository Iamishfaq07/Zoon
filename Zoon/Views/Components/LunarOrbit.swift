import SwiftUI

/// The ORBIT visual grammar: Today's hero for Sleep Intelligence.
///
/// Evolves `SleepIntelligenceOrb` rather than replacing its logic -- the
/// segment geometry (one arc per `SleepIntelligenceScore.Component`, sized by
/// `weightUsed`, absent when the score excluded it) is identical, so the
/// ring can never show a confident arc for data that wasn't there. What
/// changes is the presentation:
///
/// * Full-width, centred, no card. The ring is the page's focal point.
/// * A thin outer *track* at 100% so the eye reads "how much of the circle
///   is filled" before reading the number.
/// * Family colours per component, muted when unselected, so the ring is a
///   calm object rather than a rainbow.
/// * Scrub around the ring with one soft haptic per component boundary.
///   The centre swaps to the selected component's detail and point
///   contribution; a tap on the centre returns to the total.
/// * Animates to its value **once** per score change (`drawOnce`). It never
///   rotates and never replays on scroll.
struct LunarOrbit: View {
    let score: SleepIntelligenceScore
    var size: CGFloat = 232
    var lineWidth: CGFloat = 14
    /// Shared with `LunarOrbitLegend` so a chip tap highlights the arc and an
    /// arc scrub highlights the chip.
    @Binding var selectedID: String?

    @State private var progress: Double = 0
    @State private var scrubFraction: CGFloat?
    @State private var lastDetent: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { Theme.Family.sleepIntelligence(score.band) }

    private static let componentColors: [String: Color] = [
        "Duration": Theme.Family.sleep,
        "Continuity": Theme.Metric.hrv,
        "Regularity": Theme.Family.recovery,
        "Recovery": Theme.Family.recovery,
        "Circadian": Theme.Family.circadian,
        "Breathing": Theme.Family.breathing,
        "Stage Pattern": Theme.Family.bodySignals
    ]

    private var selected: SleepIntelligenceScore.Component? {
        guard let selectedID else { return nil }
        return score.components.first { $0.id == selectedID }
    }

    /// Each segment's [start, end) fraction of the full ring, in component
    /// order, with a hairline gap so adjoining arcs read as separate.
    private var segments: [(component: SleepIntelligenceScore.Component, start: Double, end: Double)] {
        let gap = 0.008
        var cursor = 0.0
        return score.components.map { component in
            let span = max(0, component.weightUsed - gap)
            let result = (component, cursor, cursor + span)
            cursor += component.weightUsed
            return result
        }
    }

    var body: some View {
        ZStack {
            // Outer track: the full circle the arcs fill toward.
            Circle()
                .stroke(Theme.neutral(0.07), lineWidth: lineWidth)

            ForEach(segments, id: \.component.id) { segment in
                let isDimmed = selectedID != nil && selectedID != segment.component.id
                Circle()
                    .trim(from: 0, to: max(0, min(segment.end, progress) - segment.start))
                    .stroke(
                        color(for: segment.component).opacity(isDimmed ? 0.28 : 0.95),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(segment.start * 360 - 90))
                    .animation(Motion.respecting(reduceMotion, Motion.scrub), value: isDimmed)
            }

            // Selected arc gets a faint halo so the eye lands on it.
            if let selected, let segment = segments.first(where: { $0.component.id == selected.id }) {
                Circle()
                    .trim(from: 0, to: max(0, segment.end - segment.start))
                    .stroke(color(for: selected).opacity(0.25), style: StrokeStyle(lineWidth: lineWidth + 10, lineCap: .round))
                    .rotationEffect(.degrees(segment.start * 360 - 90))
                    .blur(radius: 6)
                    .transition(.opacity)
            }

            center
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let hit = component(at: value.location) else { return }
                    if selectedID != hit.0.id {
                        if lastDetent != nil { Haptics.scrubDetent() }
                        lastDetent = hit.1
                        withAnimation(Motion.respecting(reduceMotion, Motion.scrub)) { selectedID = hit.0.id }
                    }
                }
                .onEnded { value in
                    lastDetent = nil
                    // A tap in the centre returns to the total; a tap or drag
                    // ending on an arc leaves that arc selected.
                    if component(at: value.location) == nil, isInCenter(value.location) {
                        Haptics.tap()
                        withAnimation(Motion.respecting(reduceMotion, Motion.tap)) { selectedID = nil }
                    }
                }
        )
        .drawOnce(id: score.percent, progress: $progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep Intelligence")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Components are listed below the orbit")
    }

    private var accessibilityValue: String {
        if let selected {
            return "\(selected.label), \(selected.detail), \(Self.formattedPoints(selected.pointContribution)) points"
        }
        return "\(score.percent), \(score.band.label)"
    }

    // MARK: - Centre

    @ViewBuilder
    private var center: some View {
        if let selected {
            VStack(spacing: 4) {
                Text(selected.label)
                    .font(Theme.meaning)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text("\(Int((selected.normalized * 100).rounded()))")
                    .font(.system(size: 52, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color(for: selected))
                    .contentTransition(.numericText())
                Text(selected.detail)
                    .font(Theme.evidence)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Self.formattedPoints(selected.pointContribution)) pts")
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(selected.pointContribution >= 0 ? Theme.Family.recovery : Theme.Family.attention)
            }
            .padding(.horizontal, size * 0.18)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
        } else {
            ZoonHeroMetric(value: "\(score.percent)", meaning: score.band.label, tint: tint)
                .opacity(progress > 0.15 ? 1 : 0)
                .scaleEffect(progress > 0.15 ? 1 : 0.96)
                .animation(Motion.respecting(reduceMotion, Motion.hero), value: progress > 0.15)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
        }
    }

    // MARK: - Geometry

    /// The component whose arc contains `point`, plus its index (for the
    /// haptic detent), in the orbit's local top-left coordinate space.
    /// `nil` outside the stroke band so a drag that wanders into the centre
    /// doesn't keep re-selecting whatever arc it last crossed.
    private func component(at point: CGPoint) -> (SleepIntelligenceScore.Component, Int)? {
        let centre = CGPoint(x: size / 2, y: size / 2)
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let ringRadius = (size - lineWidth) / 2
        guard abs(distance - ringRadius) < lineWidth * 1.8 else { return nil }

        let angleDegrees = atan2(dy, dx) * 180 / .pi
        var fraction = (angleDegrees + 90) / 360
        if fraction < 0 { fraction += 1 }
        if fraction >= 1 { fraction -= 1 }

        guard let index = segments.firstIndex(where: { fraction >= $0.start && fraction < $0.end }) else { return nil }
        return (segments[index].component, index)
    }

    private func isInCenter(_ point: CGPoint) -> Bool {
        let centre = CGPoint(x: size / 2, y: size / 2)
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        return (dx * dx + dy * dy).squareRoot() < (size - lineWidth) / 2 - lineWidth * 1.8
    }

    private func color(for component: SleepIntelligenceScore.Component) -> Color {
        Self.componentColors[component.label] ?? tint
    }

    private static func formattedPoints(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded >= 0 ? "+\(rounded)" : "\(rounded)"
    }
}

/// The readable legend under the orbit -- the same components as the arcs,
/// as a wrapping row of tappable chips, so the ring is never the only way to
/// reach a component. Selecting a chip selects the arc and vice versa.
struct LunarOrbitLegend: View {
    let score: SleepIntelligenceScore
    @Binding var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(score.components) { component in
                Button {
                    Haptics.tap()
                    withAnimation(Motion.respecting(reduceMotion, Motion.tap)) {
                        selectedID = selectedID == component.id ? nil : component.id
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(LunarOrbit.legendColor(for: component))
                            .frame(width: 6, height: 6)
                        Text(component.label)
                            .font(Theme.text(12, weight: .medium))
                        Text("\(Int((component.normalized * 100).rounded()))")
                            .font(Theme.label(12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        selectedID == component.id ? Theme.neutral(0.10) : Theme.neutral(0.04),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(component.label), \(Int((component.normalized * 100).rounded()))")
                .accessibilityHint(component.detail)
                .accessibilityAddTraits(selectedID == component.id ? [.isSelected] : [])
            }
        }
    }
}

extension LunarOrbit {
    static func legendColor(for component: SleepIntelligenceScore.Component) -> Color {
        componentColors[component.label] ?? Theme.Family.sleep
    }
}

private struct LunarOrbitPreviewHost: View {
    let score: SleepIntelligenceScore
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 20) {
            LunarOrbit(score: score, selectedID: $selectedID)
            LunarOrbitLegend(score: score, selectedID: $selectedID)
        }
        .padding()
    }
}

#Preview("Lunar Orbit") {
    LunarOrbitPreviewHost(score: AppMockData.dayContext().sleepIntelligence)
        .nightBackground()
        .preferredColorScheme(.dark)
}

#Preview("Lunar Orbit - poor night, light") {
    LunarOrbitPreviewHost(score: AppMockData.poorDayContext().sleepIntelligence)
        .nightBackground()
        .preferredColorScheme(.light)
}

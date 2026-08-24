import SwiftUI

/// Today's hero: an interactive segmented ring for the Sleep Intelligence
/// score, replacing the plain Recovery ring that used to open the screen.
///
/// Recovery answers "how recovered does my body look" and keeps its own
/// place further down (`RecoveryBreakdownCard`); Sleep Intelligence answers
/// the more fundamental "how did I sleep", which is the first thing a sleep
/// app should say. Each arc is one of the score's seven components, sized by
/// the weight it actually carried tonight -- a component `SleepIntelligenceScore`
/// excluded for missing data draws no arc at all, the same "excluded, not
/// defaulted" rule the score itself already enforces, so the ring can never
/// show a confident-looking segment for data that wasn't there.
///
/// Tap a segment to see that component's own detail and point contribution
/// in the center; tap it again, or tap the center, to return to the total.
/// `TodayView` places a readable driver list beside/below the orb, so the arcs
/// are never the only way to understand the score.
struct SleepIntelligenceOrb: View {
    let score: SleepIntelligenceScore

    var size: CGFloat = 210
    var lineWidth: CGFloat = 16

    @State private var selectedID: String?
    @State private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        switch score.band {
        case .poor: Theme.Metric.recoveryLow
        case .fair: Theme.Metric.recoveryMid
        case .good: Theme.Metric.battery
        case .excellent: Theme.Metric.recoveryHigh
        }
    }

    private static let componentColors: [String: Color] = [
        "Duration": Theme.Metric.sleep,
        "Continuity": Theme.Metric.hrv,
        "Regularity": Theme.Metric.battery,
        "Recovery": Theme.Metric.recoveryHigh,
        "Circadian": Theme.Metric.strain,
        "Breathing": Theme.Metric.respiratory,
        "Architecture": Theme.Metric.temperature
    ]

    /// `score.components` only ever contains components that actually ran
    /// tonight -- `SleepIntelligenceScore.compute` excludes anything missing
    /// data before the array is built, rather than including it with a flag
    /// (that's `RecoveryScore.Component`'s shape, not this one). No filter
    /// needed here; the name stays for readability at each call site below.
    private var available: [SleepIntelligenceScore.Component] {
        score.components
    }

    private var selected: SleepIntelligenceScore.Component? {
        guard let selectedID else { return nil }
        return available.first { $0.id == selectedID }
    }

    /// Each segment's [start, end) fraction of the full ring, in component
    /// order. A thin gap between segments so adjoining components -- often
    /// close in weight -- still read as separate arcs rather than one solid
    /// ring with only a color change to mark the boundary.
    private var segments: [(component: SleepIntelligenceScore.Component, start: Double, end: Double)] {
        let gap = 0.006
        var cursor = 0.0
        return available.map { component in
            let span = max(0, component.weightUsed - gap)
            let result = (component, cursor, cursor + span)
            cursor += component.weightUsed
            return result
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.cardStroke, lineWidth: lineWidth)

            ForEach(segments, id: \.component.id) { segment in
                let isDimmed = selectedID != nil && selectedID != segment.component.id
                ZStack {
                    // The visible arc.
                    Circle()
                        .trim(from: 0, to: max(0, min(segment.end, animatedProgress) - segment.start))
                        .stroke(
                            color(for: segment.component),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .opacity(isDimmed ? 0.3 : 1)

                    // An invisible, wider stroke of the same trimmed arc,
                    // purely as a tap target -- the visible arc alone is too
                    // thin to hit reliably. A second `.stroke()`'d sibling
                    // (an ordinary View, hit-tested against its own rendered
                    // shape) rather than `.contentShape` with a hand-built
                    // Shape chain, which kept failing to typecheck across
                    // trim/rotation/strokedPath in this SDK.
                    Circle()
                        .trim(from: 0, to: max(0, min(segment.end, animatedProgress) - segment.start))
                        .stroke(Color.primary.opacity(0.001), lineWidth: lineWidth + 22)
                        .onTapGesture { select(segment.component) }
                }
                .rotationEffect(.degrees(segment.start * 360 - 90))
            }

            center
        }
        .frame(width: size, height: size)
        // Drag-around-the-ring, not just discrete taps -- the redesign
        // spec's ask for this orb specifically (item #54). `simultaneousGesture`
        // rather than `.gesture` so this doesn't take over recognition from
        // the existing per-segment/center `onTapGesture`s -- both run
        // independently instead of one cancelling the other.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let component = component(at: value.location) else { return }
                    if selectedID != component.id {
                        Haptics.tap()
                        withAnimation(.snappy(duration: 0.15)) { selectedID = component.id }
                    }
                }
        )
        .onAppear {
            guard !reduceMotion else {
                animatedProgress = 1
                return
            }
            withAnimation(Motion.hero) {
                animatedProgress = 1
            }
        }
        .onChange(of: score.percent) { _, _ in
            animatedProgress = 0
            withAnimation(Motion.hero) {
                animatedProgress = 1
            }
        }
        // One summary element rather than seven interactive sub-elements:
        // VoiceOver has no equivalent of "tap a 4pt arc," and
        // The Morning Brief exposes component details as ordinary accessible
        // text; that is the equivalent of the visual arcs for VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep Intelligence")
        .accessibilityValue("\(score.percent), \(score.band.label)")
    }

    /// The component whose arc contains `point`, in the orb's own local
    /// coordinate space (top-left origin, `size` × `size`) -- `nil` outside
    /// the ring's stroke band, so a drag that wanders into the center or
    /// past the outer edge doesn't keep re-selecting whatever arc it last
    /// crossed.
    private func component(at point: CGPoint) -> SleepIntelligenceScore.Component? {
        let center = CGPoint(x: size / 2, y: size / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let ringRadius = (size - lineWidth) / 2
        guard abs(distance - ringRadius) < lineWidth * 1.5 else { return nil }

        // atan2 in screen space (y grows downward) already increases
        // clockwise from the 3 o'clock position -- the same convention
        // `.rotationEffect(.degrees(segment.start * 360 - 90))` uses to
        // place each arc, so this is the inverse of that rotation.
        let angleDegrees = atan2(dy, dx) * 180 / .pi
        var fraction = (angleDegrees + 90) / 360
        if fraction < 0 { fraction += 1 }
        if fraction >= 1 { fraction -= 1 }

        return segments.first { fraction >= $0.start && fraction < $0.end }?.component
    }

    @ViewBuilder
    private var center: some View {
        if let selected {
            VStack(spacing: 3) {
                Text(selected.label)
                    .font(Theme.label(14, weight: .semibold))
                Text(selected.detail)
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                Text(String(format: "%+.0f pts", selected.pointContribution))
                    .font(Theme.numeral(20))
                    .monospacedDigit()
                    .foregroundStyle(selected.pointContribution >= 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow)
                    .padding(.top, 3)
            }
            .padding(.horizontal, size * 0.22)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .onTapGesture {
                Haptics.tap()
                withAnimation(.snappy(duration: 0.2)) { selectedID = nil }
            }
        } else {
            VStack(spacing: 2) {
                Text("\(score.percent)")
                    .font(Theme.numeral(48))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(score.band.label)
                    .font(Theme.label(15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private func select(_ component: SleepIntelligenceScore.Component) {
        Haptics.tap()
        withAnimation(.snappy(duration: 0.2)) {
            selectedID = (selectedID == component.id) ? nil : component.id
        }
    }

    private func color(for component: SleepIntelligenceScore.Component) -> Color {
        Self.componentColors[component.label] ?? tint
    }
}

#Preview("Sleep Intelligence Orb") {
    SleepIntelligenceOrb(score: AppMockData.dayContext().sleepIntelligence)
        .padding(40)
        .nightBackground()
        .preferredColorScheme(.dark)
}

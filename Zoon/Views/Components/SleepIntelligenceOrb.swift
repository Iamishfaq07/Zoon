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
/// `SleepIntelligenceCard` below still carries the itemized "what helped /
/// what held you back" list -- this is the at-a-glance visual, not a
/// replacement for the readable one.
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

    private var available: [SleepIntelligenceScore.Component] {
        score.components.filter(\.isAvailable)
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
            let span = max(0, component.effectiveWeight - gap)
            let result = (component, cursor, cursor + span)
            cursor += component.effectiveWeight
            return result
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)

            ForEach(segments, id: \.component.id) { segment in
                let isDimmed = selectedID != nil && selectedID != segment.component.id
                Circle()
                    .trim(from: 0, to: max(0, min(segment.end, animatedProgress) - segment.start))
                    .stroke(
                        color(for: segment.component),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(segment.start * 360 - 90))
                    .opacity(isDimmed ? 0.3 : 1)
                    // Widened, unstroked hit area -- the visible arc is thin,
                    // and a 16pt-wide target is too easy to miss on a first try.
                    .contentShape(
                        Circle()
                            .trim(from: segment.start, to: segment.end)
                            .stroke(style: StrokeStyle(lineWidth: lineWidth + 20, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    )
                    .onTapGesture { select(segment.component) }
            }

            center
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else {
                animatedProgress = 1
                return
            }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) {
                animatedProgress = 1
            }
        }
        .onChange(of: score.percent) { _, _ in
            animatedProgress = 0
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                animatedProgress = 1
            }
        }
        // One summary element rather than seven interactive sub-elements:
        // VoiceOver has no equivalent of "tap a 4pt arc," and
        // SleepIntelligenceCard right below already exposes every
        // component's detail as ordinary, accessible text -- that's the
        // textual equivalent this chart needs, not a duplicate of it here.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep Intelligence")
        .accessibilityValue("\(score.percent), \(score.band.label)")
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

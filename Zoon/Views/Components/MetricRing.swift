import SwiftUI

/// The hero recovery ring: the score, and where it came from, as one picture.
///
/// The old ring drew a single arc filled to `percent` and threw the rest
/// away. Recovery is a weighted sum of four signals -- HRV at 45%, resting
/// heart rate 25%, sleep 20%, respiration 10% -- and none of that reached
/// the screen, so the number people looked at every morning was unexplained
/// at exactly the moment they cared about it.
///
/// Here each signal owns a slice of the circle proportional to the weight it
/// actually carried, and fills its own slice to its own value. That is not a
/// decorative rearrangement: because `percent` is defined as
/// `Σ(normalized × effectiveWeight) × 100`, the **total lit arc is still
/// exactly the score**. The ring reads at two distances -- how much of the
/// circle is lit is the number, and which slices fell short is the reason.
///
/// A signal with no data behind it carries no weight (`effectiveWeight` is
/// zero) and so draws no arc; the others are renormalised to close the
/// circle. It still appears in the legend, dimmed, because "we could not
/// measure this" and "this scored badly" must never look the same.
struct RecoveryRing: View {

    let recovery: RecoveryScore
    var size: CGFloat = 200
    var lineWidth: CGFloat = 18

    /// Degrees of breathing room between slices, so four contributions read
    /// as four rather than as one ring that changes colour.
    private let gap: Double = 3

    @State private var revealed: Double = 0
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bandColor: Color { Theme.recoveryColor(Double(recovery.percent)) }

    /// The components that actually carry weight, in ring order.
    private var slices: [Slice] {
        var cursor: Double = 0
        let live = recovery.components.filter { $0.effectiveWeight > 0 }
        let usable = 360 - gap * Double(live.count)
        return live.map { component in
            let span = component.effectiveWeight * usable
            let slice = Slice(
                component: component,
                start: cursor,
                span: span,
                color: Self.tint(for: component.label)
            )
            cursor += span + gap
            return slice
        }
    }

    private struct Slice: Identifiable {
        let component: RecoveryScore.Component
        let start: Double
        let span: Double
        let color: Color
        var id: String { component.label }
    }

    /// Each signal keeps the hue its own family already uses elsewhere, so
    /// the ring teaches the same colour language as the rest of the app
    /// rather than inventing a fifth one.
    ///
    /// The mapping is `Theme.Family`'s own, taken from its doc comments
    /// rather than chosen here: HRV is "HRV-as-readiness" (recovery,
    /// emerald), resting heart rate is a body signal (lavender), sleep is
    /// sleep (indigo), and respiration is breathing (aqua).
    private static func tint(for label: String) -> Color {
        switch label {
        case "HRV": Theme.Family.recovery
        case "Resting HR": Theme.Family.bodySignals
        case "Sleep": Theme.Family.sleep
        default: Theme.Family.breathing
        }
    }

    private static func shortLabel(for label: String) -> String {
        switch label {
        case "Resting HR": "RHR"
        case "Respiratory": "Resp"
        default: label
        }
    }

    /// How far a slice has drawn, given the single `revealed` driver.
    ///
    /// One animated value rather than one per slice: SwiftUI interpolates it
    /// once and each slice reads its own window out of it, which is what
    /// makes them arrive in sequence instead of together.
    private func progress(forSliceAt index: Int) -> Double {
        guard !reduceMotion else { return 1 }
        let n = Double(max(slices.count, 1))
        return min(1, max(0, (revealed * (n + 1) - Double(index)) / 2))
    }

    var body: some View {
        VStack(spacing: 14) {
            ring
            legend
        }
        .onAppear {
            guard !reduceMotion else {
                revealed = 1
                return
            }
            withAnimation(Motion.draw) { revealed = 1 }
        }
        .onChange(of: recovery.percent) { _, _ in
            revealed = 0
            withAnimation(reduceMotion ? nil : Motion.draw) { revealed = 1 }
        }
        // `.contain`, not `.ignore`. The legend is five real buttons now, and
        // collapsing the whole thing into one element would read the score
        // aloud correctly while making every one of them unreachable.
        .accessibilityElement(children: .contain)
    }

    private var ring: some View {
        ZStack {
            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                let lit = progress(forSliceAt: index) * slice.component.normalized
                let dimmed = selectedID != nil && selectedID != slice.id

                // The unlit remainder of this signal's slice: what it could
                // have contributed and didn't.
                //
                // Tinted with the slice's own hue rather than a neutral. The
                // first render showed why: `Theme.neutral(0.07)` is white at
                // 7% in Dark and all but vanished, so the ring read as four
                // floating arcs and "this signal fell short" was invisible --
                // while in Light the same token is black at 14% and read
                // fine. A tinted track is legible on both grounds and says
                // whose track it is. Same 0.15-ish treatment `TripleRing`
                // already uses.
                Circle()
                    .trim(from: slice.start / 360, to: (slice.start + slice.span) / 360)
                    .stroke(slice.color.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // Bloom under the lit part, so it reads as light rather than paint.
                Circle()
                    .trim(from: slice.start / 360, to: (slice.start + slice.span * lit) / 360)
                    .stroke(slice.color, style: StrokeStyle(lineWidth: lineWidth + 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 12)
                    .opacity(dimmed ? 0.12 : 0.45)

                Circle()
                    .trim(from: slice.start / 360, to: (slice.start + slice.span * lit) / 360)
                    .stroke(slice.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(dimmed ? 0.25 : 1)
            }

            content
        }
        .frame(width: size, height: size)
        .animation(Motion.respecting(reduceMotion, Motion.tap), value: selectedID)
        // The ring itself is one element: "72", "percent", "High" read as
        // three unrelated fragments is worse than useless.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var content: some View {
        if let selected = slices.first(where: { $0.id == selectedID })?.component {
            VStack(spacing: 2) {
                Text(selected.label.uppercased())
                    .font(Theme.label(10, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(Self.tint(for: selected.label))

                Text(selected.detail)
                    .font(Theme.numeral(size * 0.15))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)

                if let deviation = selected.deviationPercent {
                    Text(Self.deviationText(deviation))
                        .font(Theme.label(11, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Text("\(Int((selected.effectiveWeight * 100).rounded()))% of the score")
                    .font(Theme.label(10, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, size * 0.16)
            .transition(.opacity)
        } else {
            VStack(spacing: 0) {
                Text("RECOVERY")
                    .font(Theme.label(10, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkSecondary)

                HStack(alignment: .top, spacing: 1) {
                    // Counts up with the arcs rather than landing finished:
                    // the number and the picture are the same fact, so they
                    // should arrive together.
                    Text("\(Int((Double(recovery.percent) * min(1, revealed)).rounded()))")
                        .font(Theme.numeral(size * 0.30))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(Theme.numeral(size * 0.13))
                        .padding(.top, size * 0.05)
                }
                .foregroundStyle(bandColor)

                Text(recovery.isEstimate ? "Estimate" : recovery.band.label)
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .transition(.opacity)
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            ForEach(recovery.components) { component in
                let tint = Self.tint(for: component.label)
                let isSelected = selectedID == component.label

                Button {
                    guard component.isAvailable else { return }
                    Haptics.select()
                    selectedID = isSelected ? nil : component.label
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(component.isAvailable ? tint : Theme.neutral(0.18))
                            .frame(width: 6, height: 6)
                        Text(Self.shortLabel(for: component.label))
                            .font(Theme.label(11, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundStyle(component.isAvailable ? Theme.inkSecondary : Theme.inkTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(isSelected ? tint.opacity(0.16) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!component.isAvailable)
                .accessibilityLabel(legendAccessibilityLabel(for: component))
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.tap), value: selectedID)
    }

    private static func deviationText(_ deviation: Double) -> String {
        let rounded = Int(deviation.rounded())
        if rounded == 0 { return "At your baseline" }
        return rounded > 0 ? "\(rounded)% above baseline" : "\(abs(rounded))% below baseline"
    }

    private func legendAccessibilityLabel(for component: RecoveryScore.Component) -> String {
        guard component.isAvailable else { return "\(component.label), not measured" }
        return "\(component.label), \(component.detail), "
            + "\(Int((component.effectiveWeight * 100).rounded())) percent of the score"
    }

    private var accessibilityValue: String {
        let head = recovery.isEstimate
            ? "\(recovery.percent) percent, still building your baseline"
            : "\(recovery.percent) percent, \(recovery.band.label)"
        let parts = recovery.components
            .filter(\.isAvailable)
            .map { "\($0.label) \($0.detail)" }
            .joined(separator: ", ")
        return parts.isEmpty ? head : head + ". From " + parts
    }
}

/// Compact multi-arc ring for secondary metrics (strain, sleep, battery).
///
/// Concentric rather than side-by-side because the whole point is that these
/// three are read *together* — strain against recovery is the actual signal.
struct TripleRing: View {

    struct Arc {
        let fraction: Double
        let color: Color
        let label: String
        let value: String
    }

    let arcs: [Arc]
    var size: CGFloat = 92
    var lineWidth: CGFloat = 8

    @State private var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(Array(arcs.enumerated()), id: \.offset) { index, arc in
                let inset = CGFloat(index) * (lineWidth + 4)

                Circle()
                    .stroke(arc.color.opacity(0.15), lineWidth: lineWidth)
                    .padding(inset)

                Circle()
                    .trim(from: 0, to: animated ? min(1, max(0, arc.fraction)) : 0)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion {
                animated = true
            } else {
                withAnimation(Motion.hero.delay(0.1)) {
                    animated = true
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(arcs.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }
}

/// Horizontal gauge with a marked "typical" band — used by the vitals rows.
struct RangeGauge: View {
    /// 0...1 position of the current value.
    let position: Double
    /// 0...1 bounds of the typical band.
    let bandStart: Double
    let bandEnd: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.neutral(0.08))

                Capsule()
                    .fill(tint.opacity(0.28))
                    .frame(width: geo.size.width * max(0, bandEnd - bandStart))
                    .offset(x: geo.size.width * bandStart)

                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                    .shadow(color: tint.opacity(0.8), radius: 4)
                    .offset(x: geo.size.width * min(max(position, 0), 1) - 4.5)
            }
        }
        .frame(height: 9)
    }
}

#Preview("Rings") {
    ScrollView {
        VStack(spacing: 30) {
            RecoveryRing(recovery: AppMockData.dayContext().recovery)
            RecoveryRing(recovery: AppMockData.poorDayContext().recovery, size: 150, lineWidth: 14)
            TripleRing(arcs: [
                .init(fraction: 0.62, color: Theme.Metric.strain, label: "Load", value: "13.1"),
                .init(fraction: 0.88, color: Theme.Metric.sleep, label: "Sleep", value: "88%"),
                .init(fraction: 0.44, color: Theme.Metric.battery, label: "Energy", value: "44")
            ])
            RangeGauge(position: 0.72, bandStart: 0.3, bandEnd: 0.7, tint: Theme.Metric.hrv)
                .padding(.horizontal, 40)
        }
        .padding(40)
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}

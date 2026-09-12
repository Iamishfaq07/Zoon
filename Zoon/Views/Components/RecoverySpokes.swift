import SwiftUI

/// The four recovery signals as bars on their own axes, inside the recovery
/// ring.
///
/// The ring says how recovered you are. This says *in what shape* — whether
/// the number came from everything being middling or from three strong
/// signals and one that collapsed. Those two mornings feel completely
/// different and scored identically before.
///
/// **Why bars and not a radar polygon.** This started as one, and a closed
/// polygon cannot share a circle with type. Four axes 90° apart put every
/// edge's nearest point at `r/√2` from the centre — with the signals around
/// 0.7 that is roughly 50 points, while "65%" reaches 50, "Moderate" 67 and
/// "RECOVERY" 76. The edges cut through all three words, in both themes, and
/// growing the radar only moves the vertices: the edges still bow back across
/// the middle. Bars encode the same per-axis magnitude the outline did, and
/// they live entirely in the band between the numerals and the ring, so the
/// centre stays clear.
///
/// Each bar runs from 62% to 98% of the radius along its axis: a full-length
/// track showing what the signal could be, filled to what it is. A signal
/// with no data behind it shows an empty track under a hollow dashed marker,
/// never a middling fill — an axis that collapses because a watch was not
/// worn must not look like one that collapsed because the body was
/// struggling.
struct RecoverySpokes: View {

    let components: [RecoveryScore.Component]
    var size: CGFloat = 190

    /// Drives each bar growing outward from its base on first appearance.
    @State private var grown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var radius: CGFloat { size / 2 }

    /// Where a bar starts and where a full one ends, as fractions of radius.
    /// The inner figure is what keeps the bars off the centre type; the outer
    /// one keeps their tips off the ring stroke's inner edge.
    private var base: CGFloat { radius * 0.62 }
    private var tip: CGFloat { radius * 0.98 }

    /// Straight up for the first signal, then clockwise.
    private func angle(at index: Int) -> Angle {
        .degrees(-90 + 360 * Double(index) / Double(max(components.count, 1)))
    }

    private static func tint(for label: String) -> Color {
        switch label {
        case "HRV": Theme.Family.recovery
        case "Resting HR": Theme.Family.bodySignals
        case "Sleep": Theme.Family.sleep
        default: Theme.Family.breathing
        }
    }

    private static func symbol(for label: String) -> String {
        switch label {
        case "HRV": "waveform.path.ecg"
        case "Resting HR": "heart.fill"
        case "Sleep": "moon.fill"
        default: "lungs.fill"
        }
    }

    var body: some View {
        ZStack {
            ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
                spoke(for: component, at: index)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else {
                grown = 1
                return
            }
            withAnimation(Motion.hero.delay(0.12)) { grown = 1 }
        }
        .accessibilityHidden(true)
    }

    /// One signal: a track, the filled part, a half-way tick, and the marker.
    ///
    /// Built upright and rotated into place, so the bar geometry is written
    /// once in one orientation rather than four times in trigonometry.
    private func spoke(for component: RecoveryScore.Component, at index: Int) -> some View {
        let tint = Self.tint(for: component.label)
        let length = tip - base
        let value = component.isAvailable ? component.normalized : 0
        let filled = length * CGFloat(value) * CGFloat(grown)

        return ZStack {
            // Track — the full extent this signal could reach.
            Capsule()
                .fill(Theme.neutral(0.12))
                .frame(width: 7, height: length)
                .offset(y: -(base + length / 2))

            // Half-way tick, so a bar reads against a scale rather than only
            // against its neighbours.
            Capsule()
                .fill(Theme.neutral(0.22))
                .frame(width: 7, height: 1)
                .offset(y: -(base + length / 2))

            // The reading.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.55), tint],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 7, height: filled)
                .offset(y: -(base + filled / 2))

            marker(for: component, tint: tint)
                .offset(y: -tip)
                // Counter-rotate so every icon stays upright once the whole
                // spoke is turned onto its axis.
                .rotationEffect(-angle(at: index) - .degrees(90))
        }
        .rotationEffect(angle(at: index) + .degrees(90))
        .opacity(grown)
    }

    private func marker(for component: RecoveryScore.Component, tint: Color) -> some View {
        Image(systemName: Self.symbol(for: component.label))
            .font(Theme.text(10, weight: .semibold))
            // The disc behind it is a fixed 22 points, so the glyph has to
            // be too -- left to scale it grew straight out of its own circle
            // at accessibility sizes. What the marker identifies is spelled
            // out at full size in the score drivers below it.
            .dynamicTypeSize(...DynamicTypeSize.large)
            .foregroundStyle(component.isAvailable ? .white : Theme.inkTertiary)
            .frame(width: 22, height: 22)
            .background {
                Circle()
                    .fill(component.isAvailable ? tint : Color.clear)
                    .overlay {
                        Circle().stroke(
                            component.isAvailable ? .clear : Theme.neutral(0.25),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                        )
                    }
            }
    }
}

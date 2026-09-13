import SwiftUI

/// The recovery signals as a radar inside the ring.
///
/// The ring says how recovered you are. This says *in what shape* — whether
/// the number came from everything being middling or from three strong
/// signals and one that collapsed. Those are different mornings and scored
/// identically before.
///
/// **On the polygon crossing the centre type.** It does, and that is fine.
/// An earlier pass measured the collision — four axes put every edge's
/// nearest approach at `r/√2`, around 50 points, right where "67%" sits —
/// concluded the shape was wrong for the space, and replaced it with radial
/// bars. That was the wrong conclusion from a correct measurement. The
/// problem was never the geometry: it was drawing the polygon in a saturated
/// fill under a 0.70-opacity stroke, which made the overlap read as two
/// things fighting. Drawn as a wash under a hairline, the numerals sit on
/// top of it cleanly and the polygon reads as the ground it is.
///
/// So: pale fill, hairline outline, grid behind. Contrast does the work that
/// geometry could not.
struct RecoveryRadar: View {

    let components: [RecoveryScore.Component]
    var size: CGFloat = 190
    /// Set by tapping a marker; the ring's centre answers it.
    @Binding var selectedID: String?

    init(
        components: [RecoveryScore.Component],
        size: CGFloat = 190,
        selectedID: Binding<String?>
    ) {
        self.components = components
        self.size = size
        self._selectedID = selectedID
    }

    /// Drives the outline growing from the centre on first appearance.
    @State private var grown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var radius: CGFloat { size / 2 }

    /// Markers are solid discs and sit on their vertex, so a signal near zero
    /// would park one on top of the numerals. The vertex is drawn at the true
    /// value; only the disc is held out to this floor, which engages solely
    /// below 42% where the alternative is an unreadable centre.
    private static let markerFloor: Double = 0.42

    /// Straight up for the first signal, then clockwise.
    private func angle(at index: Int) -> Angle {
        .degrees(-90 + 360 * Double(index) / Double(max(components.count, 1)))
    }

    private func point(at index: Int, value: Double) -> CGPoint {
        let a = angle(at: index).radians
        let r = radius * CGFloat(value)
        return CGPoint(x: radius + cos(a) * r, y: radius + sin(a) * r)
    }

    /// An unavailable signal sits at the centre, never at a guess: an axis
    /// that collapsed because a watch was not worn must not look like one
    /// that collapsed because the body was struggling.
    private func value(of component: RecoveryScore.Component) -> Double {
        component.isAvailable ? component.normalized * grown : 0
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
            grid
            polygon
            markers
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else {
                grown = 1
                return
            }
            withAnimation(Motion.hero.delay(0.12)) { grown = 1 }
        }
    }

    /// Concentric rings at 25/50/75/100% plus a spoke per signal, so a vertex
    /// reads against a scale rather than only against its neighbours.
    private var grid: some View {
        ZStack {
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { step in
                webPath { _ in step }
                    .stroke(Theme.neutral(0.10), lineWidth: 0.5)
            }

            ForEach(components.indices, id: \.self) { index in
                Path { path in
                    path.move(to: CGPoint(x: radius, y: radius))
                    path.addLine(to: point(at: index, value: 1))
                }
                .stroke(Theme.neutral(0.09), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    /// The reading: a wash of the signal hues under a hairline.
    private var polygon: some View {
        webPath { index in max(0.02, value(of: components[index])) }
            .fill(
                LinearGradient(
                    colors: [
                        Theme.Family.recovery.opacity(0.14),
                        Theme.Family.sleep.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                webPath { index in max(0.02, value(of: components[index])) }
                    .stroke(Theme.Family.sleep.opacity(0.32), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    /// One closed path through every axis, at whatever radius the caller
    /// asks for — the grid rings and the reading are the same shape.
    private func webPath(_ radiusFraction: (Int) -> Double) -> Path {
        Path { path in
            guard !components.isEmpty else { return }
            for index in components.indices {
                let p = point(at: index, value: radiusFraction(index))
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }

    private var markers: some View {
        ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
            let tint = Self.tint(for: component.label)
            let plotted = max(Self.markerFloor * grown, value(of: component))
            let p = point(at: index, value: plotted)

            let isSelected = selectedID == component.id

            Image(systemName: Self.symbol(for: component.label))
                .font(Theme.text(10, weight: .semibold))
                // The disc behind it is a fixed 22 points, so the glyph has
                // to be too -- left to scale it grew out of its own circle at
                // accessibility sizes.
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
                // A selected marker wears a halo rather than growing: the
                // disc sits on its own vertex, and a marker that changed
                // size would read as the reading having changed.
                .overlay {
                    Circle()
                        .stroke(tint, lineWidth: 2)
                        .padding(-4)
                        .opacity(isSelected ? 1 : 0)
                }
                .scaleEffect(isSelected ? 1.08 : 1)
                .position(x: p.x, y: p.y)
                .opacity(grown)
                // 44 points of touch target around a 22-point disc, without
                // enlarging the drawn marker.
                .contentShape(Circle().inset(by: -11))
                .onTapGesture {
                    Haptics.select()
                    withAnimation(Motion.respecting(reduceMotion, Motion.standard)) {
                        selectedID = isSelected ? nil : component.id
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    component.isAvailable
                        ? "\(component.label), \(component.detail)"
                        : "\(component.label), not measured"
                )
                .accessibilityAddTraits(.isButton)
        }
    }
}

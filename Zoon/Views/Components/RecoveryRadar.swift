import SwiftUI

/// The four recovery signals on their own axes, inside the recovery ring.
///
/// The ring says how recovered you are. This says *in what shape* — whether
/// the number came from everything being middling or from three strong
/// signals and one that collapsed. Those two mornings feel completely
/// different and scored identically before.
///
/// One axis per signal, each plotted at its own `normalized` value, so a
/// balanced day is a regular polygon and a lopsided one is visibly lopsided.
/// The area is not meaningful and is not meant to be read as a quantity — it
/// is the *outline* that carries the information, which is why the grid rings
/// are drawn behind it rather than left implied.
///
/// A signal with no data behind it sits at the centre with a hollow marker,
/// never at a middling value: an axis that collapses because a watch was not
/// worn must not look like an axis that collapsed because the body was
/// struggling.
struct RecoveryRadar: View {

    let components: [RecoveryScore.Component]
    var size: CGFloat = 150

    /// Drives the outline growing from the centre on first appearance.
    @State private var grown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var radius: CGFloat { size / 2 }

    /// Straight up for the first axis, then clockwise. Four signals make a
    /// diamond; the shape follows the data rather than being padded out to a
    /// pentagon it has no fifth signal for.
    private func angle(at index: Int) -> Angle {
        .degrees(-90 + 360 * Double(index) / Double(max(components.count, 1)))
    }

    private func point(at index: Int, value: Double) -> CGPoint {
        let a = angle(at: index).radians
        let r = radius * value
        return CGPoint(x: radius + cos(a) * r, y: radius + sin(a) * r)
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
            outline
            vertices
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

    /// Concentric rings at 25/50/75/100% plus a spoke per signal, so a vertex
    /// can be read against a scale instead of only against its neighbours.
    private var grid: some View {
        ZStack {
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { step in
                Path { path in
                    guard !components.isEmpty else { return }
                    for index in components.indices {
                        let p = point(at: index, value: step)
                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                }
                .stroke(Theme.neutral(0.10), lineWidth: 1)
            }

            ForEach(components.indices, id: \.self) { index in
                Path { path in
                    path.move(to: CGPoint(x: radius, y: radius))
                    path.addLine(to: point(at: index, value: 1))
                }
                .stroke(Theme.neutral(0.08), lineWidth: 1)
            }
        }
    }

    private var outline: some View {
        Path { path in
            guard !components.isEmpty else { return }
            for (index, component) in components.enumerated() {
                // An unavailable signal sits at the centre, not at a guess.
                let value = component.isAvailable ? component.normalized * grown : 0
                let p = point(at: index, value: max(0.02, value))
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Theme.Family.sleep.opacity(0.30), Theme.Family.recovery.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            Path { path in
                guard !components.isEmpty else { return }
                for (index, component) in components.enumerated() {
                    let value = component.isAvailable ? component.normalized * grown : 0
                    let p = point(at: index, value: max(0.02, value))
                    if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
            }
            .stroke(Theme.Family.sleep.opacity(0.75), lineWidth: 1.5)
        }
    }

    private var vertices: some View {
        ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
            let tint = Self.tint(for: component.label)
            let p = point(at: index, value: 1)

            Image(systemName: Self.symbol(for: component.label))
                .font(Theme.text(11, weight: .semibold))
                .foregroundStyle(component.isAvailable ? .white : Theme.inkTertiary)
                .frame(width: 24, height: 24)
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
                .position(x: p.x, y: p.y)
                .opacity(grown)
        }
    }
}

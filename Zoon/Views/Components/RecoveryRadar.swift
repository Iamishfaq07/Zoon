import SwiftUI

/// The recovery signals as a radar inside the ring.
///
/// The ring says how recovered you are. This says *in what shape* — whether
/// the number came from everything being middling or from three strong
/// signals and one that collapsed. Those are different mornings and scored
/// identically before.
///
/// **Identity and value are drawn separately**, which is the change that
/// fixed the overlap in the hero. Each signal's icon sits at a fixed point on
/// its axis and stays there; the polygon vertex moves with the true value.
/// Previously the icon *was* the vertex, held out to a 42% floor so it would
/// not land on the numerals — which put it on them anyway at a radar radius
/// of 95, and made every value below 42% plot in the same place.
/// `RecoveryRadarGeometry` carries that reasoning and the numbers.
///
/// **On the polygon crossing the centre type.** It still may, and that is
/// still fine. An earlier pass measured the collision, concluded the shape
/// was wrong for the space, and replaced it with radial bars; that was the
/// wrong conclusion from a correct measurement. The problem was never the
/// geometry — it was a saturated fill under a heavy stroke, which made the
/// overlap read as two things fighting. Drawn as a wash that fades out
/// through the centre, under a hairline, the numerals sit on top of it
/// cleanly and the polygon reads as the ground it is.
struct RecoveryRadar: View {

    let components: [RecoveryScore.Component]
    var size: CGFloat = 190
    /// Set by tapping an icon; the ring's centre answers it.
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

    /// Drives the polygon growing from the centre on first appearance.
    @State private var grown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var radius: CGFloat { size / 2 }
    private var count: Int { components.count }

    /// An unavailable signal sits at the centre, never at a guess: an axis
    /// that collapsed because a watch was not worn must not look like one
    /// that collapsed because the body was struggling.
    private func value(of component: RecoveryScore.Component) -> Double {
        component.isAvailable ? component.normalized : 0
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
            valueDots
            icons
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

    /// Fades the web out through the centre so the score sits on clean
    /// ground. A mask rather than a clip: a hard edge would draw a visible
    /// disc, and the point is that nothing there draws attention.
    private var centreFade: some View {
        RadialGradient(
            colors: [.clear, .clear, .white],
            center: .center,
            startRadius: 0,
            endRadius: RecoveryRadarGeometry.centreExclusionRadius(radarRadius: radius) * 1.15
        )
    }

    /// Concentric rings and a spoke per signal, so a vertex reads against a
    /// scale rather than only against its neighbours.
    private var grid: some View {
        ZStack {
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { step in
                webPath { _ in step }
                    .stroke(Theme.neutral(0.10), lineWidth: 0.5)
            }

            ForEach(components.indices, id: \.self) { index in
                Path { path in
                    path.move(to: CGPoint(x: radius, y: radius))
                    path.addLine(to: RecoveryRadarGeometry.point(
                        index: index, count: count, radarRadius: radius,
                        distance: RecoveryRadarGeometry.dataRadius(radarRadius: radius)
                    ))
                }
                .stroke(Theme.neutral(0.09), lineWidth: 0.5)
            }
        }
        .mask(centreFade)
        .accessibilityHidden(true)
    }

    /// The reading: a wash of the signal hues under a hairline.
    private var polygon: some View {
        let shape = webPath { index in max(0.015, value(of: components[index]) * grown) }
        return shape
            .fill(
                LinearGradient(
                    colors: [
                        Theme.Family.recovery.opacity(0.16),
                        Theme.Family.sleep.opacity(0.11)
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                shape.stroke(Theme.Family.sleep.opacity(0.34), lineWidth: 1)
            }
            .mask(centreFade)
            .accessibilityHidden(true)
    }

    /// A dot at each true vertex, where there is room for one.
    ///
    /// Small and unlabelled: it marks the value precisely for anybody reading
    /// the shape closely, and carries no identity, so it can sit anywhere the
    /// polygon can. Suppressed inside the exclusion zone, where the score
    /// takes precedence and the collapsed polygon already says "very low".
    private var valueDots: some View {
        ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
            let normalized = value(of: component)
            if component.isAvailable, RecoveryRadarGeometry.drawsValueDot(normalized: normalized) {
                let point = RecoveryRadarGeometry.valuePoint(
                    index: index, count: count, radarRadius: radius,
                    normalized: normalized * grown
                )
                Circle()
                    .fill(Self.tint(for: component.label))
                    .frame(width: 5, height: 5)
                    .position(x: point.x, y: point.y)
                    .opacity(grown)
            }
        }
        .accessibilityHidden(true)
    }

    /// The identity layer: one icon per axis, at a fixed point, whatever the
    /// value is.
    ///
    /// These are the touch targets. `contentShape` widens each one well past
    /// its drawn bounds so the 22-point disc still clears the 44-point
    /// minimum, which it could not do at its own size.
    private var icons: some View {
        ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
            let tint = Self.tint(for: component.label)
            let point = RecoveryRadarGeometry.iconPoint(
                index: index, count: count, radarRadius: radius
            )
            let isSelected = selectedID == component.id
            let diameter = RecoveryRadarGeometry.iconDiameter

            Image(systemName: Self.symbol(for: component.label))
                .font(Theme.text(10, weight: .semibold))
                // The icon is an axis label inside a fixed-diameter circle;
                // it cannot scale with the setting without leaving the ring.
                // Nothing is lost — every reading it stands for is repeated
                // at full size in the drivers directly below.
                .dynamicTypeSize(...DynamicTypeSize.large)
                .foregroundStyle(iconForeground(component, tint: tint, isSelected: isSelected))
                .frame(width: diameter, height: diameter)
                .background {
                    Circle()
                        .fill(iconFill(component, tint: tint, isSelected: isSelected))
                        .overlay {
                            Circle().stroke(
                                component.isAvailable
                                    ? (isSelected ? tint : .clear)
                                    : Theme.neutral(0.25),
                                style: StrokeStyle(
                                    lineWidth: isSelected ? 2 : 1,
                                    dash: component.isAvailable ? [] : [2, 2]
                                )
                            )
                        }
                }
                .position(x: point.x, y: point.y)
                .opacity(grown)
                // 44-point target around a 22-point mark.
                .contentShape(Circle().inset(by: -(44 - diameter) / 2))
                .onTapGesture {
                    Haptics.select()
                    withAnimation(Motion.respecting(reduceMotion, Motion.standard)) {
                        selectedID = isSelected ? nil : component.id
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(component, isSelected: isSelected))
                .accessibilityAddTraits(
                    isSelected ? [.isButton, .isSelected] : [.isButton]
                )
        }
    }

    /// Selected reads as an outlined mark rather than a filled one, so the
    /// emphasis is a change of state and not a change of weight — a heavier
    /// disc at the perimeter pulls the eye off the score it is explaining.
    private func iconFill(
        _ component: RecoveryScore.Component, tint: Color, isSelected: Bool
    ) -> Color {
        guard component.isAvailable else { return .clear }
        return isSelected ? tint.opacity(0.18) : tint
    }

    private func iconForeground(
        _ component: RecoveryScore.Component, tint: Color, isSelected: Bool
    ) -> Color {
        guard component.isAvailable else { return Theme.inkTertiary }
        return isSelected ? tint : .white
    }

    private func accessibilityLabel(
        _ component: RecoveryScore.Component, isSelected: Bool
    ) -> String {
        guard component.isAvailable else { return "\(component.label), not measured" }
        return isSelected
            ? "\(component.label), \(component.detail), selected"
            : "\(component.label), \(component.detail)"
    }

    /// One closed path through every axis, at whatever fraction of the data
    /// radius the caller asks for — the grid rings and the reading are the
    /// same shape.
    private func webPath(_ radiusFraction: (Int) -> Double) -> Path {
        Path { path in
            guard !components.isEmpty else { return }
            for index in components.indices {
                let p = RecoveryRadarGeometry.valuePoint(
                    index: index, count: count, radarRadius: radius,
                    normalized: radiusFraction(index)
                )
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }
}

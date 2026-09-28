import SwiftUI

/// Horizon metaphor for Tomorrow / Tonight: a sequence of nodes, one sleep band.
struct HorizonStrip: View {

    let nodes: [ZoonTomorrow.Node]
    let sleepWindowStart: Date
    let sleepWindowEnd: Date
    var selectedID: String?
    var onSelect: (ZoonTomorrow.Node) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let t0 = nodes.first?.date.timeIntervalSince1970 ?? 0
        let t1 = nodes.last?.date.timeIntervalSince1970 ?? 1
        let span = max(1, t1 - t0)

        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.neutral(0.14))
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                        .offset(y: 7)

                    let sleepX = CGFloat((sleepWindowStart.timeIntervalSince1970 - t0) / span)
                    let sleepW = CGFloat((sleepWindowEnd.timeIntervalSince1970 - sleepWindowStart.timeIntervalSince1970) / span)
                    Capsule()
                        .fill(Theme.Metric.sleep.opacity(0.35))
                        .frame(width: max(18, sleepW * (width - 20)), height: 10)
                        .offset(x: 10 + sleepX * (width - 20), y: 3)

                    ForEach(nodes) { node in
                        let x = CGFloat((node.date.timeIntervalSince1970 - t0) / span)
                        Button {
                            Haptics.select()
                            onSelect(node)
                        } label: {
                            Circle()
                                .fill(tint(for: node.kind))
                                .frame(width: selectedID == node.id ? 14 : 10, height: selectedID == node.id ? 14 : 10)
                                .shadow(color: selectedID == node.id ? tint(for: node.kind).opacity(0.5) : .clear, radius: 6)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6 + x * (width - 20))
                        .accessibilityLabel("\(node.title), \(node.date.formatted(date: .omitted, time: .shortened)). \(node.detail)")
                    }
                }
            }
            .frame(height: 22)

            // Captions sit under their own dot, then are pushed apart so
            // they cannot collide.
            //
            // Two earlier attempts each failed one way. An `HStack` of equal
            // columns never overlapped but pointed at the wrong dot whenever
            // the times were not evenly spaced. Positioning each caption on
            // its own dot fixed that and introduced the opposite bug: on a
            // real evening Wind-down and Sleep window are ninety minutes
            // apart and Wake and Event are fifty, so on a phone those pairs
            // printed straight through one another -- "Wsilnedd-odwonw".
            //
            // So: alternate rows, which separates neighbours that are close
            // in time, and a declutter pass within each row that enforces a
            // minimum gap and clamps to the edges. Alignment degrades
            // gracefully under pressure instead of the text becoming
            // unreadable.
            // Past the accessibility sizes no horizontal arrangement works:
            // six captions at that scale need more width than a phone has,
            // and the declutter pass can only pick which of two bad outcomes
            // to produce. So the strip stops being a strip and becomes a
            // list, which cannot overlap at any size.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(nodes) { node in
                        // Above AX3 the label and the time stop sharing a
                        // line. "Wind-down" wraps to two lines at those
                        // sizes, which squeezes the time column until an
                        // eight-character clock time no longer fits it --
                        // and the AX5 capture shows exactly what that
                        // produces: "10:22 P" on one line and "M" on the
                        // next. Given the whole width the time cannot be
                        // squeezed at all.
                        if dynamicTypeSize >= .accessibility4 {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Circle()
                                        .fill(tint(for: node.kind))
                                        .frame(width: 8, height: 8)
                                    Text(node.title)
                                        .font(Theme.label(10, weight: .semibold))
                                        .foregroundStyle(Theme.inkTertiary)
                                }
                                Text(ClockText.atomic(node.date))
                                    .font(Theme.label(11, weight: .semibold))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(tint(for: node.kind))
                                    .frame(width: 8, height: 8)
                                Text(node.title)
                                    .font(Theme.label(10, weight: .semibold))
                                    .foregroundStyle(Theme.inkTertiary)
                                Spacer(minLength: 8)
                                Text(ClockText.atomic(node.date))
                                    .font(Theme.label(11, weight: .semibold))
                                    .monospacedDigit()
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // A key under the strip, two to a row, each with its own
                // dot. Captions placed under their dots had to be shrunk and
                // stacked to fit six labels into a phone's width -- on a
                // real evening "Now", "Sleep window" and "Wind-down" sat on
                // top of one another. A key cannot collide at any time
                // spacing; the dot colour ties each entry to its place.
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12, alignment: .leading),
                              GridItem(.flexible(), spacing: 12, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(nodes) { node in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(tint(for: node.kind))
                                .frame(width: 8, height: 8)
                            Text(node.title)
                                .font(Theme.label(12, weight: .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                            Spacer(minLength: 4)
                            Text(ClockText.atomic(node.date))
                                .font(Theme.label(13, weight: .semibold))
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tint(for kind: ZoonTomorrow.Node.Kind) -> Color {
        switch kind {
        case .now: Theme.ink
        case .caffeine: Theme.Metric.strain
        case .windDown: Theme.Metric.temperature
        case .sleep: Theme.Metric.sleep
        case .wake: Theme.Metric.battery
        case .event: Theme.Metric.recoveryHigh
        }
    }
}

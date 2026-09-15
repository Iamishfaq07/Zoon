import SwiftUI

/// Horizon metaphor for Tomorrow / Tonight: a sequence of nodes, one sleep band.
struct HorizonStrip: View {
    let nodes: [ZoonTomorrow.Node]
    let sleepWindowStart: Date
    let sleepWindowEnd: Date
    var selectedID: String?
    var onSelect: (ZoonTomorrow.Node) -> Void = { _ in }

    /// Wide enough for "Wind-down" over a short time.
    private let captionWidth: CGFloat = 56
    /// One caption row. Captions alternate between two of these.
    private let rowHeight: CGFloat = 30
    /// The closest two captions in the *same* row may sit, centre to centre.
    /// Below this they are pushed apart.
    private var minimumCaptionGap: CGFloat { captionWidth + 4 }

    /// Caption centres: ideal time-proportional positions, then separated.
    ///
    /// Two passes over each row. Left to right guarantees the minimum gap and
    /// the left edge; right to left restores the right edge, which the first
    /// pass can violate when it pushes a run of close nodes rightward. Nodes
    /// arrive sorted by time, so index order is position order.
    private func captionLayout(width: CGFloat, t0: TimeInterval, span: TimeInterval) -> [CGFloat] {
        let half = captionWidth / 2
        var centres = nodes.map { node -> CGFloat in
            let x = CGFloat((node.date.timeIntervalSince1970 - t0) / span)
            return 11 + x * max(0, width - 20)
        }
        guard width > captionWidth else { return centres }

        for row in 0..<2 {
            let indices = centres.indices.filter { $0 % 2 == row }
            guard indices.count > 1 else { continue }
            for (position, index) in indices.enumerated() {
                let floor = position == 0 ? half : centres[indices[position - 1]] + minimumCaptionGap
                centres[index] = max(centres[index], floor)
            }
            for (position, index) in indices.enumerated().reversed() {
                let ceiling = position == indices.count - 1
                    ? width - half
                    : centres[indices[position + 1]] - minimumCaptionGap
                centres[index] = min(centres[index], ceiling)
            }
            // A row too crowded to satisfy both edges: keep everything on
            // screen rather than letting the first pass win and pushing the
            // last caption off the right edge.
            for index in indices {
                centres[index] = min(max(centres[index], half), width - half)
            }
        }
        return centres
    }

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
            GeometryReader { geo in
                let layout = captionLayout(width: geo.size.width, t0: t0, span: span)
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    VStack(spacing: 2) {
                        Text(node.title)
                            .font(Theme.label(10, weight: .semibold))
                            .foregroundStyle(Theme.inkTertiary)
                        Text(node.date.formatted(date: .omitted, time: .shortened))
                            .font(Theme.label(11, weight: .semibold))
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: captionWidth)
                    .position(
                        x: layout[index],
                        y: index.isMultiple(of: 2) ? rowHeight / 2 : rowHeight * 1.5
                    )
                }
            }
            .frame(height: rowHeight * 2)
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

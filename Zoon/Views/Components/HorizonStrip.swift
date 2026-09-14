import SwiftUI

/// Horizon metaphor for Tomorrow / Tonight: a sequence of nodes, one sleep band.
struct HorizonStrip: View {
    let nodes: [ZoonTomorrow.Node]
    let sleepWindowStart: Date
    let sleepWindowEnd: Date
    var selectedID: String?
    var onSelect: (ZoonTomorrow.Node) -> Void = { _ in }

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

            HStack(alignment: .top, spacing: 0) {
                ForEach(nodes) { node in
                    VStack(spacing: 2) {
                        Text(node.title)
                            .font(Theme.label(10, weight: .semibold))
                            .foregroundStyle(Theme.inkTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(node.date.formatted(date: .omitted, time: .shortened))
                            .font(Theme.label(11, weight: .semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
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

import SwiftUI

/// The TIMELINE visual grammar: a vertical sequence of moments with a
/// connecting spine and a "now" marker that progresses down it through the
/// day. Used for Tonight on Today; the same component will carry Sleep
/// Story, Night Detective and Autopilot elsewhere.
///
/// Each node can carry a second line of detail -- that's how Tonight folds
/// in what used to be three cards: the countdown becomes the header, the
/// autopilot target and shift become the Bed node's detail.
struct ZoonTimeline: View {
    struct Node: Identifiable {
        let id: String
        let time: Date
        let title: String
        var detail: String?
        var symbol: String
        var tint: Color
        /// A node that carries a recommendation gets a heavier mark.
        var isEmphasised = false
    }

    let nodes: [Node]
    var now: Date = .now

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    private var sorted: [Node] { nodes.sorted { $0.time < $1.time } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, node in
                row(node, isLast: index == sorted.count - 1, index: index)
            }
        }
        .drawOnce(id: nodes.map(\.id).joined(), progress: $progress)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline")
    }

    private func row(_ node: Node, isLast: Bool, index: Int) -> some View {
        let isPast = node.time <= now
        let revealed = progress >= Double(index) / Double(max(sorted.count, 1))
        return HStack(alignment: .top, spacing: 14) {
            // Time column, right-aligned so the spine lines up.
            Text(node.time, format: .dateTime.hour().minute())
                .font(Theme.label(13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isPast ? .tertiary : .primary)
                .frame(width: 52, alignment: .trailing)
                .padding(.top, 2)

            // Spine + mark.
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isPast ? Theme.neutral(0.18) : node.tint.opacity(node.isEmphasised ? 1 : 0.85))
                        .frame(width: node.isEmphasised ? 14 : 10, height: node.isEmphasised ? 14 : 10)
                    if isPast {
                        Image(systemName: "checkmark")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 14, height: 18)
                if !isLast {
                    spine(from: node, isPast: isPast)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: node.symbol)
                        .font(Theme.text(11, weight: .semibold))
                        .foregroundStyle(isPast ? AnyShapeStyle(.tertiary) : AnyShapeStyle(node.tint))
                    Text(node.title)
                        .font(Theme.label(14, weight: node.isEmphasised ? .semibold : .medium))
                        .foregroundStyle(isPast ? .secondary : .primary)
                }
                if let detail = node.detail {
                    Text(detail)
                        .font(Theme.evidence)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 18)

            Spacer(minLength: 0)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 6)
        .animation(Motion.respecting(reduceMotion, .easeOut(duration: 0.25)), value: revealed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.time.formatted(.dateTime.hour().minute())), \(node.title)\(node.detail.map { ". \($0)" } ?? "")\(isPast ? ", done" : "")")
    }

    /// The segment of spine below a node. Past segments are filled; the
    /// segment that "now" is inside is filled to the current fraction, so the
    /// marker visibly moves down the day.
    private func spine(from node: Node, isPast: Bool) -> some View {
        GeometryReader { geo in
            let next = sorted.first { $0.time > node.time }
            let fraction: CGFloat = {
                guard let next else { return isPast ? 1 : 0 }
                guard now > node.time else { return 0 }
                guard now < next.time else { return 1 }
                return CGFloat(now.timeIntervalSince(node.time) / next.time.timeIntervalSince(node.time))
            }()
            ZStack(alignment: .top) {
                Rectangle().fill(Theme.neutral(0.10)).frame(width: 2)
                Rectangle().fill(Theme.Family.sleep.opacity(0.7)).frame(width: 2, height: geo.size.height * fraction)
                if fraction > 0 && fraction < 1 {
                    Circle()
                        .fill(Theme.dialMarker)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.Family.sleep, lineWidth: 1.5))
                        .offset(y: geo.size.height * fraction - 4)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 22)
    }
}

#Preview("Timeline") {
    let cal = Calendar.current
    let t = { (h: Int, m: Int, dayOffset: Int) -> Date in
        cal.date(bySettingHour: h, minute: m, second: 0, of: .now.addingTimeInterval(Double(dayOffset) * 86400)) ?? .now
    }
    return ScrollView {
        ZoonTimeline(nodes: [
            .init(id: "caffeine", time: t(14, 0, 0), title: "Caffeine cutoff", symbol: "cup.and.saucer.fill", tint: Theme.Metric.strain),
            .init(id: "winddown", time: t(21, 45, 0), title: "Wind down", detail: "Dim the lights, screens away", symbol: "moon.haze.fill", tint: Theme.Family.circadian),
            .init(id: "bed", time: t(22, 35, 0), title: "Bed", detail: "20m earlier than usual · repays 30m of debt", symbol: "bed.double.fill", tint: Theme.Family.sleep, isEmphasised: true),
            .init(id: "asleep", time: t(22, 55, 0), title: "Target asleep", symbol: "zzz", tint: Theme.Family.sleep),
            .init(id: "wake", time: t(6, 50, 1), title: "Wake", symbol: "sunrise.fill", tint: Theme.Metric.battery)
        ])
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}

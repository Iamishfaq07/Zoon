import Foundation

/// Places captions next to chart anchors so they do not write through
/// each other, or through the readout above the plot.
///
/// `.position` centres a view on a point and does not know about its
/// neighbours. Energy Horizon used that, so a peak and an afternoon dip
/// 90 minutes apart — which heavy sleep debt produces — landed on the
/// same pixels: "Peak focus" written through "Afternoon dip".
///
/// The layout is geometry only. It does not know about energy, sleep, or
/// type. Callers pass boxes; they get boxes that do not overlap, clamped
/// to the canvas. A caption that cannot sit on either side without
/// colliding is dropped: the anchor (the dot) stays, the words go. That
/// is better than two sentences occupying one place.
enum ChartLabelLayout {

    enum Side: Equatable, Sendable {
        case above, below
        var opposite: Side { self == .above ? .below : .above }
    }

    struct Request: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var prefersAbove: Bool
    }

    struct Placement: Equatable, Sendable {
        var x: Double
        var y: Double
        var side: Side
        var showCaption: Bool
    }

    /// Distance from the anchor to the caption centre, in the same units
    /// as the request.
    static let defaultOffset: Double = 20
    static let defaultGap: Double = 4
    static let defaultMargin: Double = 2

    static func place(
        _ items: [Request],
        canvasWidth: Double,
        canvasHeight: Double,
        offset: Double = defaultOffset,
        gap: Double = defaultGap,
        margin: Double = defaultMargin
    ) -> [Placement] {
        guard !items.isEmpty else { return [] }

        var placed: [(index: Int, placement: Placement, box: Box)] = []
        let order = items.indices.sorted { items[$0].x < items[$1].x }

        for index in order {
            let item = items[index]
            let halfW = item.width / 2
            let x = clamp(item.x, halfW + margin, max(halfW + margin, canvasWidth - halfW - margin))

            func captionY(_ side: Side) -> Double {
                let raw = side == .above ? item.y - offset : item.y + offset
                let lo = item.height / 2 + margin
                let hi = canvasHeight - item.height / 2 - margin
                guard hi >= lo else { return canvasHeight / 2 }
                return clamp(raw, lo, hi)
            }

            func fits(_ side: Side) -> Bool {
                let y = side == .above ? item.y - offset : item.y + offset
                return y - item.height / 2 >= margin && y + item.height / 2 <= canvasHeight - margin
            }

            var side: Side = item.prefersAbove ? .above : .below
            if !fits(side), fits(side.opposite) {
                side = side.opposite
            }

            func candidate(_ side: Side, show: Bool) -> (Placement, Box) {
                let y = captionY(side)
                let placement = Placement(x: x, y: y, side: side, showCaption: show)
                let box = show
                    ? Box(
                        minX: x - halfW,
                        maxX: x + halfW,
                        minY: y - item.height / 2,
                        maxY: y + item.height / 2
                    )
                    : Box(minX: x, maxX: x, minY: item.y, maxY: item.y)
                return (placement, box)
            }

            func hits(_ box: Box, side: Side, show: Bool) -> Bool {
                guard show else { return false }
                return placed.contains {
                    $0.placement.showCaption && $0.box.intersects(box, gap: gap, sameSide: $0.placement.side == side)
                }
            }

            var (placement, box) = candidate(side, show: true)
            if hits(box, side: side, show: true) {
                (placement, box) = candidate(side.opposite, show: true)
                if hits(box, side: side.opposite, show: true) {
                    (placement, box) = candidate(side, show: false)
                }
            }
            placed.append((index, placement, box))
        }

        var result = Array(repeating: Placement(x: 0, y: 0, side: .above, showCaption: false), count: items.count)
        for entry in placed {
            result[entry.index] = entry.placement
        }
        return result
    }

    private struct Box {
        var minX: Double
        var maxX: Double
        var minY: Double
        var maxY: Double

        func intersects(_ other: Box, gap: Double, sameSide: Bool) -> Bool {
            let xOverlap = minX < other.maxX + gap && other.minX < maxX + gap
            // Same lane: X is enough. Two wide captions 24 pt apart look
            // stacked even when their boxes miss by a few points on Y —
            // that is the Peak-focus / Afternoon-dip screenshot.
            if sameSide { return xOverlap }
            return xOverlap
                && minY < other.maxY + gap
                && other.minY < maxY + gap
        }
    }

    private static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(value, lo), hi)
    }
}

import SwiftUI

/// Lays items out in a row, wrapping to the next line when they no longer fit.
///
/// **Why this exists.** Rows of pills were `HStack`s. An `HStack` never wraps:
/// it compresses its children instead, and at accessibility text sizes that
/// turned a "Sample" pill into a column of single letters and broke "93 score"
/// into "93 / scor / e". The text was legible in the sense of being large, and
/// unreadable in every sense that matters.
///
/// Wrapping is the layout answer to the problem, rather than
/// `minimumScaleFactor`, which solves it by making accessibility text small
/// again — which is the one thing the reader asked it not to be.
///
/// Items keep their natural width, so at ordinary sizes this behaves exactly
/// like the `HStack` it replaces and the screens do not change. An item wider
/// than the container gets a line to itself and is allowed to use all of it.
struct ZoonFlowLayout: Layout {

    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    /// Where each line sits when it does not fill the width.
    var alignment: HorizontalAlignment = .center

    struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Internal rather than private so the wrapping arithmetic can be tested
    /// directly. A `Layout` is otherwise only observable by hosting it, and
    /// the line-breaking is the part with something to get wrong.
    func lines(
        sizes: [CGSize],
        proposedWidth: CGFloat
    ) -> [Line] {
        // A nil or infinite proposal means "size to fit", which for a wrapping
        // layout is one line. Anything else wraps to the width offered.
        let limit = proposedWidth.isFinite && proposedWidth > 0 ? proposedWidth : .greatestFiniteMagnitude
        var result: [Line] = []
        var current = Line()

        for (index, size) in sizes.enumerated() {
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > limit {
                result.append(current)
                current = Line()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.width = needed
                current.height = max(current.height, size.height)
                current.indices.append(index)
            }
        }
        if !current.indices.isEmpty { result.append(current) }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let laid = lines(sizes: sizes, proposedWidth: proposal.width ?? .greatestFiniteMagnitude)
        let width = laid.map(\.width).max() ?? 0
        let height = laid.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(0, laid.count - 1))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let laid = lines(sizes: sizes, proposedWidth: bounds.width)
        var y = bounds.minY

        for line in laid {
            var x: CGFloat = switch alignment {
            case .leading: bounds.minX
            case .trailing: bounds.maxX - line.width
            default: bounds.minX + (bounds.width - line.width) / 2
            }
            // A single item wider than the line starts at the leading edge and
            // is offered the whole width, rather than being centred and
            // spilling off both sides.
            if line.width > bounds.width { x = bounds.minX }

            for index in line.indices {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    proposal: ProposedViewSize(
                        width: min(size.width, bounds.width), height: size.height
                    )
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }
}

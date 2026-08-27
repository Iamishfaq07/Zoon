import SwiftUI

/// Makes a custom-drawn chart speak.
///
/// A `Chart`, a `Canvas` or a hand-built `Path` renders nothing to
/// VoiceOver. The pixels carry the whole message, so a screen reader
/// reaches the card, reads its title, and then finds an empty box where
/// the data is. Nine of this app's fifteen custom-drawn views were in that
/// state -- not degraded, silent.
///
/// The fix is not a label saying "chart". It is a spoken summary carrying
/// what a sighted reader takes from the shape in one glance: where the
/// value is now, and which way it has been going. That has to be computed
/// from the same data the chart draws, which is why this takes strings the
/// caller derives rather than trying to introspect the plot.
///
/// `children: .ignore` is deliberate. Chart marks generate their own
/// per-point elements, and on a thirty-night series that is thirty swipes
/// of "value, value, value" before reaching anything else. One summary the
/// reader can act on beats thirty data points they have to assemble
/// themselves.
extension View {

    /// - Parameters:
    ///   - label: what the chart is. A noun phrase, not "chart of...".
    ///   - summary: where the value is now and where it has been heading.
    func chartSummary(_ label: String, _ summary: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(summary)
    }
}

/// Describes the direction of a series in words, for `chartSummary`.
///
/// Deliberately coarse. A screen-reader summary that reports "down 3.4%"
/// implies a precision the underlying nightly data does not have, and the
/// same three-word verdict is what a sighted reader takes from the slope.
enum ChartTrend {

    /// Compares the last third of a series against the first third.
    ///
    /// Thirds rather than first-versus-last point: two endpoints can differ
    /// by noise on any single pair of nights, and a summary that flips
    /// between "rising" and "falling" on one unusual night is worse than no
    /// summary at all.
    static func describe(_ values: [Double], higherIsBetter: Bool = true) -> String {
        guard values.count >= 6 else { return "not enough nights to show a direction yet" }
        let third = values.count / 3
        guard let start = Statistics.median(Array(values.prefix(third))),
              let end = Statistics.median(Array(values.suffix(third))) else {
            return "not enough nights to show a direction yet"
        }

        let scale = max(abs(start), 1)
        let change = (end - start) / scale
        guard abs(change) >= 0.05 else { return "roughly level" }

        let rising = change > 0
        let better = rising == higherIsBetter
        return "\(rising ? "rising" : "falling"), which is \(better ? "an improvement" : "a decline")"
    }
}

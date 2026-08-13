import SwiftUI
import Charts

/// The floating readout every interactive chart in the app shows on tap or
/// drag — the actual numbers behind the point currently under your finger.
///
/// Every chart previously only had axis labels and gridlines to read a value
/// off of, which is imprecise by design in Swift Charts (that's what
/// gridlines are for) and gives no way to check one specific night's number.
/// `chartXSelection` turns tap-and-drag into a bound Date with no gesture code
/// of its own; this is the shared badge every chart's selection renders into.
struct ChartSelectionBadge: View {
    let title: String
    let lines: [(label: String, value: String, tint: Color)]

    @Environment(\.colorScheme) private var colorScheme

    init(title: String, lines: [(label: String, value: String, tint: Color)]) {
        self.title = title
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.text(9, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 5) {
                    Circle().fill(line.tint).frame(width: 6, height: 6)
                    Text(line.label)
                        .font(Theme.text(10))
                        .foregroundStyle(.secondary)
                    Text(line.value)
                        .font(Theme.label(12, weight: .bold))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            // Same fix as GlassCard (Theme.swift): a bare .ultraThinMaterial
            // with no fill on top of it reads as glass in Dark but washes
            // out to near-invisible against Light's pale ground. This badge
            // predates that fix and was missed because it doesn't route
            // through .glassCard() -- it needs its own copy of the same
            // colorScheme-aware material + cardFill combination.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.cardFill)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        }
        .fixedSize()
    }
}

extension Array where Element == SleepNightFeatures {
    /// The element whose `date` falls on the same calendar day as `target` —
    /// every day-bucketed chart (`x: .value(..., unit: .day)`) needs this to
    /// resolve `chartXSelection`'s raw Date back to one specific night, since
    /// the selection lands anywhere within that day's bar, not exactly on it.
    func nearest(toDay target: Date) -> Element? {
        first { Calendar.current.isDate($0.date, inSameDayAs: target) }
    }
}

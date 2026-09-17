import SwiftUI

/// Today's settled periods, as a list of clock ranges with what was measured
/// in each.
///
/// **Why there is no "0 today" state.** An empty list and an empty HealthKit
/// store produce the same array, and a card that said "no settled periods
/// today" would be making a claim about physiology out of an absence of data.
/// The card renders nothing at all when the engine found nothing, which is the
/// same rule `RestorativeWindow.summary` follows.
///
/// **Why the sentence is repeated once, not per row.** The claim is identical
/// for every window — that is the point of it being a fixed sentence rather
/// than a generated one — and stamping it on each row would read as four
/// separate findings instead of one kind of finding observed four times. Each
/// row carries only what differs: when, how long, and the two numbers behind
/// it.
struct RestorativeWindowsCard: View {
    let windows: [RestorativeWindow.Window]

    var body: some View {
        if !windows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Settled periods",
                    subtitle: RestorativeWindow.summary(windows),
                    systemImage: "waveform.path.ecg"
                )

                Text(windows[0].sentence)
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(windows) { window in
                    row(window)
                    if window.id != windows.last?.id {
                        Rectangle().fill(Theme.cardStroke).frame(height: 1)
                    }
                }

                // Named once for the day rather than per row: four copies of
                // the same caveat reads as four problems.
                if windows.allSatisfy({ $0.medianHRV == nil }) {
                    Text("Heart rate only — no HRV readings in today's windows.")
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .glassCard()
        }
    }

    private func row(_ window: RestorativeWindow.Window) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // The clock range and the duration are one fact read two ways, so
            // they sit on one line until the type is wide enough that they
            // cannot, and then they stack rather than truncate.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(range(window))
                        .font(Theme.numeral(16))
                    Spacer(minLength: 0)
                    Text(window.minutes.pluralized("minute"))
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(range(window))
                        .font(Theme.numeral(16))
                    Text(window.minutes.pluralized("minute"))
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            Text(window.evidence)
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Coverage is the only thing graded, so it is only named when it
            // is short of full -- a "high confidence" badge on every row
            // teaches the reader to stop reading the badge.
            if window.confidence < .high {
                Text("\(Int((window.coverage * 100).rounded()))% heart-rate coverage in this window.")
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(range(window)), \(window.minutes.pluralized("minute"))")
        .accessibilityValue("\(window.sentence) \(window.evidence)")
    }

    private func range(_ window: RestorativeWindow.Window) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(window.start.formatted(style))–\(window.end.formatted(style))"
    }
}

#Preview {
    let start = Date.now.addingTimeInterval(-3 * 3600)
    return ScrollView {
        RestorativeWindowsCard(
            windows: [
                RestorativeWindow.Window(
                    start: start,
                    end: start.addingTimeInterval(24 * 60),
                    medianHeartRate: 63,
                    baselineHeartRate: 71,
                    medianHRV: 58,
                    coveredBins: 5,
                    totalBins: 5
                ),
                RestorativeWindow.Window(
                    start: start.addingTimeInterval(7200),
                    end: start.addingTimeInterval(7200 + 20 * 60),
                    medianHeartRate: 66,
                    baselineHeartRate: 71,
                    medianHRV: nil,
                    coveredBins: 3,
                    totalBins: 4
                )
            ]
        )
        .padding()
    }
    .nightBackground()
}

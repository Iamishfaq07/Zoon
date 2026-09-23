import SwiftUI

/// Compact phase brief. Why / confidence / data used wait behind a tap.
struct AdaptiveBriefCard: View {
    let brief: AdaptiveZoonBrief.Result
    @State private var showsWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zoon brief")
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Family.sleep)
            Text(brief.headline)
                .font(Theme.label(16, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showsWhy.toggle()
            } label: {
                Text(showsWhy ? "Hide why" : "Why?")
                    .font(Theme.label(12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows confidence and which data this sentence used")
            if showsWhy {
                if let why = brief.why {
                    Text(why)
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(brief.confidence)
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkTertiary)
                if !brief.dataUsed.isEmpty {
                    Text("Data used: \(brief.dataUsed.joined(separator: ", "))")
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

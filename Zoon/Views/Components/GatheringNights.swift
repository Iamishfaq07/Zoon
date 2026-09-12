import SwiftUI

/// "Zoon needs more nights", drawn as the thing it actually is: a moon filling.
///
/// Ten screens were already saying this in words — "needs 14 nights", "not
/// enough history yet", "no night yet" — while showing `clock`,
/// `questionmark.circle` or `sparkles` next to the sentence. None of those
/// glyphs says anything about sleep, and none of them says how far along you
/// are.
///
/// A moon lit to `nights ÷ needed` says both. It is the same moon the week
/// strip and the Today hero draw, so an empty screen is recognisably the same
/// app as a full one, and the picture is true rather than decorative: new moon
/// on the first night, full when the screen has what it needs.
struct GatheringNights: View {
    let title: String
    let message: String
    /// Nights counted so far.
    var nights: Int
    /// Nights this screen needs before it has anything to show.
    var needed: Int

    private var fill: Double {
        guard needed > 0 else { return 0 }
        return min(1, Double(nights) / Double(needed))
    }

    private var isReady: Bool { nights >= needed }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the one-time reveal. An empty screen is the screen most likely
    /// to be read as "the app is broken", and a moon that arrives is the
    /// cheapest possible signal that something is running.
    @State private var risen = false

    var body: some View {
        VStack(spacing: 18) {
            MoonWell(fill: fill, metNeed: isReady, size: 104)
                .scaleEffect(risen ? 1 : 0.88)
                .opacity(risen ? 1 : 0)
                .onAppear {
                    guard !reduceMotion else {
                        risen = true
                        return
                    }
                    withAnimation(Motion.hero) { risen = true }
                }

            VStack(spacing: 8) {
                Text(title)
                    .font(Theme.label(19, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(Theme.text(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Only where a count means something. "1 of 1 nights" on a
                // screen waiting for its first night is noise, and the moon
                // already says it.
                if needed > 1 {
                    Text(countLine)
                        .font(Theme.label(12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .entrance(1)
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var countLine: String {
        let remaining = max(0, needed - nights)
        guard remaining > 0 else { return "Enough nights now" }
        return "\(nights) of \(needed) nights · \(remaining) to go"
    }

    private var accessibilityLabel: String {
        needed > 1 ? "\(title). \(message) \(countLine)" : "\(title). \(message)"
    }
}

#Preview("Gathering nights") {
    ScrollView {
        VStack(spacing: 36) {
            GatheringNights(
                title: "Building your body clock",
                message: "Zoon needs 14 nights of history before it can estimate your preferred sleep window.",
                nights: 0,
                needed: 14
            )
            GatheringNights(
                title: "Building your body clock",
                message: "Zoon needs 14 nights of history before it can estimate your preferred sleep window.",
                nights: 6,
                needed: 14
            )
            GatheringNights(
                title: "Not enough history yet",
                message: "Zoon needs a few more nights before it can chart a trend.",
                nights: 2,
                needed: 3
            )
            GatheringNights(
                title: "No night yet",
                message: "Zoon needs last night's data before there's anything to ask about.",
                nights: 0,
                needed: 1
            )
        }
        .padding(.vertical, 40)
    }
    .zoonPreviewEnvironment()
}

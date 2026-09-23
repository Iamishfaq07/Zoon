import SwiftUI

/// The single action worth the reader's attention, or nothing.
///
/// Zoon has many engines. Showing all of them is a list. This is the one
/// `OneThing` picked, with the reason it won. An empty view on an ordinary
/// day is a real answer, not a missing card.
struct OneThingCard: View {
    let selection: OneThing.Selection?

    var body: some View {
        if let selection {
            VStack(alignment: .leading, spacing: 8) {
                Text("One thing")
                    .font(Theme.kicker)
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkSecondary)

                Text(selection.candidate.action)
                    .font(Theme.text(17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(selection.candidate.reason)
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("One thing. \(selection.candidate.action) \(selection.candidate.reason)")
        }
    }
}

import SwiftUI

struct MovementContextCard: View {
    let snapshot: MovementContext.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Movement", systemImage: "figure.walk")
            Text(snapshot.sentence)
                .font(Theme.text(15))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(snapshot.provenance). Context only — not part of Sleep Intelligence or Recovery.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.sentence)
    }
}

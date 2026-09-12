import SwiftUI
import SwiftData

/// How Zoon's mind changed about each thing you log.
///
/// The Evidence screen shows what Zoon believes now. This shows how it got
/// there -- and, when it happens, that it once believed something else.
///
/// ## Why the recording happens here
///
/// `EvidenceLedgerStore.record` is idempotent by design: it writes only when
/// the belief has materially changed (see `EvidenceLedger.Revision`), so it
/// is safe to call on every appearance and that is exactly how it is called.
/// A rule that only applies when someone remembers to apply it is not a rule.
///
/// Doing it from the screen that displays beliefs, rather than from the
/// refresh pipeline, keeps the whole feature to one file and one dependency
/// -- the view's own `modelContext`. The cost is that a belief is recorded
/// when someone looks rather than the moment it forms, so a revision's
/// timestamp is "when Zoon first showed you this", not "when the data first
/// supported it". That is a real limitation and the copy does not pretend
/// otherwise.
/// `@MainActor` on the view itself, not only on `body`: the helpers below
/// construct and call `EvidenceLedgerStore`, which is MainActor-isolated like
/// every other store here, and a private helper on a View does not inherit
/// that isolation on its own.
@MainActor
struct EvidenceHistoryView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    @State private var history: [EvidenceLedger.Revision] = []

    private var ledger: EvidenceLedgerStore { EvidenceLedgerStore(context: modelContext) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("What Zoon believed, and when. Earlier readings are never overwritten -- if a longer stretch of nights changes the answer, both are here.")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                let claims = EvidenceLedger.claimIDs(in: history)
                if claims.isEmpty {
                    Text("Nothing recorded yet. Once Zoon can compare enough of your nights to say something about a habit, the first reading lands here and stays.")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                } else {
                    ForEach(claims, id: \.self) { claimID in
                        claimCard(claimID)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("How this changed")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            history = ledger.allRevisions()
        }
    }

    @ViewBuilder
    private func claimCard(_ claimID: String) -> some View {
        let timeline = EvidenceLedger.timeline(for: claimID, in: history)

        VStack(alignment: .leading, spacing: 10) {
            Text(timeline.last?.headline ?? claimID)
                .font(Theme.label(15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(timeline.enumerated()), id: \.element.id) { index, revision in
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == timeline.count - 1 ? Theme.Family.sleep : Theme.neutral(0.25))
                            .frame(width: 7, height: 7)
                        if index < timeline.count - 1 {
                            Rectangle()
                                .fill(Theme.neutral(0.15))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 7)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(revision.recordedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.inkTertiary)
                        Text(revision.status.label)
                            .font(Theme.label(13, weight: .semibold))
                        Text(evidenceLine(revision))
                            .font(Theme.evidence)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // "Why did this change?" -- the timeline already
                        // shows *that* a belief moved; this says why. Absent
                        // on the first revision, which did not change from
                        // anything.
                        if index > 0 {
                            let change = EvidenceLedger.change(from: timeline[index - 1], to: revision)
                            if !change.whyLine.isEmpty {
                                Text(change.whyLine)
                                    .font(Theme.evidence)
                                    .foregroundStyle(change.isComparable ? Color.secondary : Theme.Family.attention)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// The effect and what it rested on, or just what it rested on.
    ///
    /// The sample size is always present. A revision without it is a claim
    /// with no way to judge it, which is the state this whole screen exists
    /// to move away from.
    private func evidenceLine(_ revision: EvidenceLedger.Revision) -> String {
        var parts: [String] = []
        if let effect = revision.effect, let unit = revision.effectUnit {
            parts.append(String(format: "%+.0f %@", effect, unit))
        }
        parts.append(revision.sampleSize == 1 ? "1 matched night" : "\(revision.sampleSize) matched nights")
        return parts.joined(separator: " · ")
    }


}

#Preview("How this changed") {
    NavigationStack { EvidenceHistoryView() }
        .zoonPreviewEnvironment()
}

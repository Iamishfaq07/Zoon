import Foundation
import SwiftData

/// Reads and appends the evidence history.
///
/// Deliberately thin. Every decision about *whether* a belief is worth
/// recording lives in `EvidenceLedger`, which is pure and tested; this only
/// fetches what is already there, asks, and inserts. Splitting it that way is
/// what lets the interesting half be exercised without a store at all.
@MainActor
struct EvidenceLedgerStore {

    let context: ModelContext

    /// Every revision, in no particular order -- callers use
    /// `EvidenceLedger.timeline(for:in:)` or `claimIDs(in:)`, so sorting here
    /// would be a second ordering to keep in step with those.
    func allRevisions() -> [EvidenceLedger.Revision] {
        (try? context.fetch(FetchDescriptor<EvidenceRevisionRecord>()))?
            .map(\.revision) ?? []
    }

    func timeline(for claimID: String) -> [EvidenceLedger.Revision] {
        EvidenceLedger.timeline(for: claimID, in: allRevisions())
    }

    /// Records `candidate` if it says something the claim's history does not
    /// already say.
    ///
    /// Safe to call on every refresh -- that is the design. A rule only
    /// applied when someone remembers to apply it is not a rule, so the
    /// "is this worth keeping" decision is inside rather than at each call
    /// site.
    ///
    /// - Returns: true when a revision was written.
    @discardableResult
    func record(_ candidate: EvidenceLedger.Revision) -> Bool {
        let history = allRevisions()
        let updated = EvidenceLedger.recording(candidate, into: history)
        guard updated.count > history.count else { return false }
        context.insert(EvidenceRevisionRecord(candidate))
        try? context.save()
        return true
    }
}

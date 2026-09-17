import Foundation
import Observation

/// A signal the person invented — "magnesium", "evening medication",
/// "prayer".
///
/// Observational by default and permanently. Zoon knows nothing about what a
/// custom behaviour *is*, only when it was logged, so it may describe an
/// association and may never recommend one.
struct CustomBehavior: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var symbol: String
    var isActive: Bool

    init(id: UUID = UUID(), name: String, symbol: String = "circle.fill", isActive: Bool = true) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.isActive = isActive
    }

    var behaviorID: BehaviorID { .custom(id) }
}

/// Every behaviour the app can currently name, built-in and custom.
///
/// Passed into the correlator rather than reached for globally, so the
/// analysis is a pure function of its inputs and a test can hand it a
/// catalogue without a store behind it.
struct BehaviorCatalog: Hashable, Sendable {

    let custom: [CustomBehavior]

    init(custom: [CustomBehavior] = []) {
        self.custom = custom
    }

    /// Built-ins only. The default everywhere a caller genuinely has no
    /// custom behaviours to offer.
    static let builtInOnly = BehaviorCatalog()

    /// What a logging surface should offer: every built-in, then the custom
    /// behaviours still switched on.
    var loggable: [BehaviorID] {
        BehaviorTag.allCases.map(\.behaviorID) + custom.filter(\.isActive).map(\.behaviorID)
    }

    /// What the analysis should test.
    ///
    /// Every custom behaviour, including the ones switched off. Deactivating
    /// a signal stops Zoon asking about it; it does not retract the nights
    /// already logged, and dropping those from the analysis would make a
    /// finding vanish because the person tidied up their prompt list.
    var analysable: [BehaviorID] {
        BehaviorTag.allCases.map(\.behaviorID) + custom.map(\.behaviorID)
    }

    func behavior(for id: BehaviorID) -> CustomBehavior? {
        guard case let .custom(uuid) = id else { return nil }
        return custom.first { $0.id == uuid }
    }

    /// A name for any identity, including one whose definition has been
    /// deleted.
    ///
    /// A deleted custom behaviour leaves its observations behind — they are
    /// the person's data, and a finding built on them is still true — so the
    /// catalogue has to be able to label an id it no longer holds. "A removed
    /// signal" is honest; printing a bare UUID is not.
    func label(for id: BehaviorID) -> String {
        switch id {
        case let .builtIn(tag): tag.label
        case .custom: behavior(for: id)?.name ?? "A removed signal"
        }
    }

    func symbol(for id: BehaviorID) -> String {
        switch id {
        case let .builtIn(tag): tag.symbol
        case .custom: behavior(for: id)?.symbol ?? "circle.dashed"
        }
    }
}

@MainActor
@Observable
final class CustomBehaviorStore {
    static let shared = CustomBehaviorStore()
    private static let key = "zoon.customBehaviors.v1"
    private(set) var behaviors: [CustomBehavior]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([CustomBehavior].self, from: data) {
            behaviors = decoded
        } else { behaviors = [] }
    }

    private let defaults: UserDefaults

    var catalog: BehaviorCatalog { BehaviorCatalog(custom: behaviors) }

    /// - Returns: the behaviour, so a caller can log against it immediately.
    @discardableResult
    func add(name: String, symbol: String = "circle.fill") -> CustomBehavior? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !behaviors.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return nil }
        let behavior = CustomBehavior(name: trimmed, symbol: symbol)
        behaviors.append(behavior)
        save()
        return behavior
    }

    func toggle(_ behavior: CustomBehavior) {
        guard let index = behaviors.firstIndex(where: { $0.id == behavior.id }) else { return }
        behaviors[index].isActive.toggle(); save()
    }

    /// Removes the *definition*.
    ///
    /// The observations stay. They are answers the person gave, and a
    /// matched-pair finding built on thirty nights does not stop being true
    /// because the prompt was tidied away. `BehaviorCatalog.label(for:)`
    /// knows how to name an id it no longer holds. Delete Everything is what
    /// removes the data, and it already does.
    func remove(_ behavior: CustomBehavior) { behaviors.removeAll { $0.id == behavior.id }; save() }

    /// Restores definitions from a backup.
    ///
    /// Matched on identity, not on name: the identity is what the restored
    /// observations are keyed by, so a signal renamed since the backup has to
    /// keep the id it was logged under or its history is orphaned. An
    /// existing definition wins, the same rule every other importer follows —
    /// what is on this device is more trustworthy than what is in an older
    /// archive.
    /// - Returns: how many definitions were added.
    @discardableResult
    func importBehaviors(_ imported: [CustomBehavior]) -> Int {
        let existing = Set(behaviors.map(\.id))
        let existingNames = Set(behaviors.map { $0.name.lowercased() })
        var added = 0
        for behavior in imported
        where !existing.contains(behavior.id) && !existingNames.contains(behavior.name.lowercased()) {
            behaviors.append(behavior)
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    /// Delete Everything. Removes the key rather than saving an empty list so
    /// nothing of the user's is left behind in defaults.
    func deleteAll() { behaviors = []; defaults.removeObject(forKey: Self.key) }

    private func save() { defaults.set(try? JSONEncoder().encode(behaviors), forKey: Self.key) }
}

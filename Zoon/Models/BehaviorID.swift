import Foundation

/// One behaviour's identity, whether Zoon shipped it or the person invented
/// it.
///
/// Custom behaviours already had a store, a settings screen and a row of
/// capsules on the journal. What they did not have was anywhere to *go*: the
/// capsules were not tappable, nothing was recorded, and no engine had ever
/// heard of them. They were labels for a feature that did not exist.
///
/// The storage layer, as it happens, was ready. `BehaviorObservationRecord`
/// keys on a `String` rather than on `BehaviorTag`, and `BehaviorAnswers`
/// already exposes `state(forIdentifier:)` — both for forward-compatibility
/// reasons unrelated to this. So a custom behaviour needs no new table and no
/// migration; it needs an identity the rest of the app can carry, which is
/// this.
///
/// `identifier` is the canonical spelling and the only thing that is ever
/// persisted. Built-ins keep their bare raw value so every row ever written
/// still joins.
enum BehaviorID: Hashable, Sendable, Codable {
    case builtIn(BehaviorTag)
    case custom(UUID)

    /// Prefix for custom identifiers.
    ///
    /// A colon cannot appear in a `BehaviorTag` raw value (they are camelCase
    /// Swift case names), so the two namespaces cannot collide. It also
    /// avoids `|`, which `BehaviorObservationRecord.identity` uses to join
    /// the night key to the behaviour.
    static let customPrefix = "custom:"

    var identifier: String {
        switch self {
        case let .builtIn(tag): tag.rawValue
        case let .custom(id): Self.customPrefix + id.uuidString
        }
    }

    /// Round-trips `identifier`. `nil` for a string this build does not
    /// recognise — a behaviour written by a future version decays to
    /// "ignored" rather than failing the whole read, the same decay strategy
    /// `JournalEntry.tags` uses.
    init?(identifier: String) {
        if identifier.hasPrefix(Self.customPrefix) {
            let raw = String(identifier.dropFirst(Self.customPrefix.count))
            guard let uuid = UUID(uuidString: raw) else { return nil }
            self = .custom(uuid)
        } else if let tag = BehaviorTag(rawValue: identifier) {
            self = .builtIn(tag)
        } else {
            return nil
        }
    }

    var builtIn: BehaviorTag? {
        if case let .builtIn(tag) = self { return tag }
        return nil
    }

    var isCustom: Bool { builtIn == nil }

    // Encoded as the identifier string, not as a tagged enum. Persisted
    // behaviour identities appear in exports and in the evidence ledger, and
    // a flat string is the form those already store.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = BehaviorID(identifier: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognised behaviour identifier \(raw)"
            ))
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}

extension BehaviorTag {
    var behaviorID: BehaviorID { .builtIn(self) }
}

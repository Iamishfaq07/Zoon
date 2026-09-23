import Foundation

/// Small in-memory cache of model-generated insights, keyed by what the model
/// was asked.
///
/// **Keyed by prompt, not by night.** This used to be keyed by the night's
/// date alone, so once a night had text, that text was served for the rest of
/// the process: after a correction to the night, a goal change, or a vital
/// that arrived late. And a later `prepare` that failed left the old text in
/// place, so the screen went on showing a summary of numbers that were no
/// longer the night's numbers. The key is now the prompt and instructions
/// themselves -- every input the model saw -- so different inputs cannot find
/// the same entry, and every attempt invalidates its night first.
///
/// Deliberately not persisted: a model-generated insight is cheap to
/// regenerate and shouldn't outlive the process, and caching generated health
/// text to disk invites it drifting out of sync with the data it describes.
///
/// Lock-guarded rather than actor-isolated, because `SleepInsightEngine.generate`
/// is synchronous and non-isolated — a `@MainActor` cache could not be read from
/// it without making the whole protocol async, which the rule engine has no
/// reason to pay for.
final class InsightCache: @unchecked Sendable {

    static let shared = InsightCache()

    /// Bumped when the prompt's meaning changes without its text changing.
    static let algorithmVersion = 2

    struct Key: Hashable, Sendable {
        fileprivate let value: String
    }

    private struct Entry {
        let night: Date
        let insight: SleepInsight
    }

    private var storage: [Key: Entry] = [:]
    private let lock = NSLock()

    init() {}

    static func key(prompt: String, instructions: String) -> Key {
        Key(value: "\(algorithmVersion)\u{1F}\(instructions)\u{1F}\(prompt)")
    }

    func value(for key: Key) -> SleepInsight? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]?.insight
    }

    func store(_ insight: SleepInsight, for key: Key, night: Date) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = Entry(night: night, insight: insight)
        // A handful of nights is all that's ever read back.
        if storage.count > 4 {
            let oldest = storage.sorted { $0.value.night < $1.value.night }.prefix(storage.count - 4)
            for (key, _) in oldest { storage.removeValue(forKey: key) }
        }
    }

    /// Drops everything generated for this night, whatever it was asked.
    func invalidate(night: Date) {
        lock.lock()
        defer { lock.unlock() }
        storage = storage.filter { $0.value.night != night }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

/// Whether generated text states only numbers its prompt contained.
enum GeneratedTextGrounding {

    /// Numbers are grounded when the prompt contains them, or when they are
    /// a prompt figure in minutes expressed as whole hours (420 -> 7) or as
    /// hours and minutes (445 -> 7 and 25). Numbers of one digit up to 3 are
    /// allowed as ordinary language ("one", "2 things"); anything else is a
    /// claim and needs a source.
    static func isGrounded(_ text: String, in prompt: String) -> Bool {
        let stated = numbers(in: text)
        guard !stated.isEmpty else { return true }
        var allowed = Set(numbers(in: prompt))
        for value in allowed where value >= 60 {
            allowed.insert((value / 60).rounded(.down))
            allowed.insert((value / 60).rounded())
            allowed.insert(value.truncatingRemainder(dividingBy: 60).rounded())
        }
        return stated.allSatisfy { value in
            value <= 3 || allowed.contains(value) || allowed.contains(value.rounded())
        }
    }

    static func numbers(in text: String) -> [Double] {
        var result: [Double] = []
        var current = ""
        func flush() {
            let trimmed = current.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if let value = Double(trimmed), value.isFinite { result.append(value) }
            current = ""
        }
        for character in text {
            if character.isASCII, character.isNumber || (character == "." && !current.isEmpty) {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}

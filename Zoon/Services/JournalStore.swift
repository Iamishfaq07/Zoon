import Foundation
import SwiftData
import os

/// SwiftData access for journal entries.
@MainActor
final class JournalStore {

    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "JournalStore")

    init(context: ModelContext) {
        self.context = context
    }

    /// Nights that carry at least one tag.
    ///
    /// An entry with no tags is a row the user opened and left alone; counting
    /// it would award the journal badge for scrolling past the screen.
    func taggedNightCount() -> Int {
        allEntries().filter { !$0.tags.isEmpty }.count
    }

    func allEntries() -> [JournalEntry] {
        let descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func entry(for date: Date) -> JournalEntry? {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.date == day })
        return try? context.fetch(descriptor).first
    }

    /// Fetches the entry for a day, creating an empty one if needed.
    ///
    /// Returning a live model object rather than a value type is deliberate: the
    /// journal screen toggles tags directly on it, and SwiftData's change
    /// tracking then drives the view update with no plumbing.
    @discardableResult
    func entryOrCreate(for date: Date) -> JournalEntry {
        if let existing = entry(for: date) { return existing }
        let entry = JournalEntry(date: date)
        context.insert(entry)
        save()
        return entry
    }

    func toggle(_ tag: BehaviorTag, on date: Date) {
        let entry = entryOrCreate(for: date)
        entry.toggle(tag)
        save()
    }

    func setNote(_ note: String?, on date: Date) {
        let entry = entryOrCreate(for: date)
        entry.note = (note?.isEmpty ?? true) ? nil : note
        entry.updatedAt = .now
        save()
    }

    func setFeeling(_ feeling: MorningFeeling?, on date: Date) {
        let entry = entryOrCreate(for: date)
        entry.feeling = feeling
        save()
    }

    /// Days that have at least one tag — for the journal's history list.
    func taggedDays() -> [JournalEntry] {
        allEntries().filter { !$0.tagIdentifiers.isEmpty }
    }

    /// Restores journal entries from a backup.
    ///
    /// Existing entries win on conflict: a tag you set on this device is more
    /// trustworthy than one from an older archive.
    /// - Returns: how many entries were created.
    @discardableResult
    func importEntries(_ records: [(date: Date, tags: [String], note: String?, feelingRaw: Int?)]) -> Int {
        var created = 0
        for record in records {
            let day = Calendar.current.startOfDay(for: record.date)
            guard entry(for: day) == nil else { continue }
            let entry = JournalEntry(date: day)
            entry.tagIdentifiers = record.tags
            entry.note = record.note
            entry.feelingRaw = record.feelingRaw
            context.insert(entry)
            created += 1
        }
        save()
        return created
    }

    @discardableResult
    func deleteAll() -> Bool {
        do {
            try context.delete(model: JournalEntry.self)
            try context.save()
            return true
        } catch {
            logger.error("Journal delete-all failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Journal save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

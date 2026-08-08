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

    /// Days that have at least one tag — for the journal's history list.
    func taggedDays() -> [JournalEntry] {
        allEntries().filter { !$0.tagIdentifiers.isEmpty }
    }

    func deleteAll() {
        do {
            try context.delete(model: JournalEntry.self)
            try context.save()
        } catch {
            logger.error("Journal delete-all failed: \(error.localizedDescription, privacy: .public)")
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

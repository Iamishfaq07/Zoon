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
    ///
    /// - Parameter nightKey: The matching night's `SleepNightFeatures.nightKey`,
    ///   when the caller has one (see `JournalEntry.nightKey`). Stamped onto a
    ///   newly created entry, and backfilled onto an existing one that
    ///   predates this field -- same progressive-backfill pattern
    ///   `SleepHistoryStore.upsert` already uses for `SleepNightRecord.nightKey`.
    ///   `nil` for callers with no specific night in view (a watch quick
    ///   action logged against "today," a day the picker shows before any
    ///   night exists for it yet); those entries keep matching by `date`
    ///   alone until something does supply a key for them.
    @discardableResult
    func entryOrCreate(for date: Date, nightKey: String? = nil) -> JournalEntry {
        if let existing = entry(for: date) {
            if existing.nightKey == nil, let nightKey {
                existing.nightKey = nightKey
                save()
            }
            return existing
        }
        let entry = JournalEntry(date: date, nightKey: nightKey)
        context.insert(entry)
        save()
        return entry
    }

    /// Looks an entry up by the night it's actually about, falling back to
    /// `date` for entries written before `nightKey` existed. See
    /// `SleepDataCoordinator.journalObservations()` for why the fallback
    /// matters: `date` alone can silently mismatch after the user travels.
    func entry(forNightKey nightKey: String, fallbackDate date: Date) -> JournalEntry? {
        let descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.nightKey == nightKey })
        if let keyed = try? context.fetch(descriptor).first {
            return keyed
        }
        return entry(for: date)
    }

    func toggle(_ tag: BehaviorTag, on date: Date, nightKey: String? = nil) {
        let entry = entryOrCreate(for: date, nightKey: nightKey)
        entry.toggle(tag)
        save()
    }

    func setNote(_ note: String?, on date: Date, nightKey: String? = nil) {
        let entry = entryOrCreate(for: date, nightKey: nightKey)
        entry.note = (note?.isEmpty ?? true) ? nil : note
        entry.updatedAt = .now
        save()
    }

    func setFeeling(_ feeling: MorningFeeling?, on date: Date, nightKey: String? = nil) {
        let entry = entryOrCreate(for: date, nightKey: nightKey)
        entry.feeling = feeling
        save()
    }

    /// Sets one Morning Check-In V2 dimension (rested/energy/sleepiness/mood).
    /// Each dimension saves independently so a partial check-in still persists.
    func setCheckIn(_ dimension: CheckInDimension, value: Int?, on date: Date, nightKey: String? = nil) {
        let entry = entryOrCreate(for: date, nightKey: nightKey)
        entry.setValue(value, for: dimension)
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
    func importEntries(
        _ records: [(
            date: Date, tags: [String], note: String?, feelingRaw: Int?,
            restedRaw: Int?, energyRaw: Int?, sleepinessRaw: Int?, moodRaw: Int?
        )]
    ) -> Int {
        var created = 0
        for record in records {
            let day = Calendar.current.startOfDay(for: record.date)
            guard entry(for: day) == nil else { continue }
            let entry = JournalEntry(date: day)
            entry.tagIdentifiers = record.tags
            entry.note = record.note
            entry.feelingRaw = record.feelingRaw
            entry.restedRaw = record.restedRaw
            entry.energyRaw = record.energyRaw
            entry.sleepinessRaw = record.sleepinessRaw
            entry.moodRaw = record.moodRaw
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

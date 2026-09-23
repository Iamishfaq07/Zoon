import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Export and re-import Zoon's local data.
///
/// A local-first app owes the user this. If the promise is "your data never
/// leaves the device", the corollary has to be "and you can take it with you" —
/// otherwise local-first is just lock-in with better marketing.
///
/// Two formats, for two different jobs:
/// - **JSON** — complete and re-importable. This is the backup.
/// - **CSV** — one row per night, opens in any spreadsheet. This is for people
///   who want to do their own analysis, which is exactly the kind of user this
///   app should be encouraging.
///
/// Neither format touches the network. `ShareLink` hands a file to the system
/// share sheet and the user decides where it goes.
enum DataExporter {

    /// Version stamped into every export so a future importer can migrate
    /// older files instead of rejecting them.
    ///
    /// V3 adds secondary sleep episodes (naps/secondary-sleep HealthKit
    /// auto-detected but never selected as a night's main sleep), completed
    /// Guided Experiment outcomes, overnight sound-event metadata, and a
    /// few preference fields V2 never carried. Every new field is Optional
    /// on `Archive` and `PreferencesRecord`, so a V1/V2 file (missing all of
    /// them) still decodes cleanly -- see `JournalRecord`'s own doc comment
    /// for why that's the load-bearing compatibility mechanism here rather
    /// than a hand-written migration.
    /// 4 adds `behaviorObservations`. Bumped rather than left at 3
    /// because a V3 archive genuinely cannot round-trip a V4 store: the
    /// three-state behaviour answers have no representation in it, and
    /// restoring one would silently return every behaviour to unknown.
    /// Older archives still import -- the field is optional and the
    /// version guard is `<=`.
    /// 6 adds behaviour detail (quantity, unit, event time, intensity) to
    /// each observation, and alertness-check sessions. Both are optional,
    /// so a 5 or older archive decodes and imports them as absent.
    static let formatVersion = 6

    struct Archive: Codable {
        let formatVersion: Int
        let exportedAt: Date
        let goalMinutes: Double
        let nights: [SleepNightFeatures]
        let journal: [JournalRecord]
        let naps: [NapStore.Nap]
        /// Optional for backward compatibility with format 1 exports.
        let preferences: PreferencesRecord?
        let snoreSummaries: [SnoreStore.NightSummary]?
        let wristTemperatures: [WristTemperatureRecord]?
        /// Secondary sleep episodes (naps, secondary-sleep blocks) --
        /// `nil` for any export made before format 3.
        let episodes: [EpisodeRecord]?
        /// Completed Guided Experiment outcomes -- `nil` before format 3.
        let experiments: [SleepExperimentStore.Outcome]?
        /// Most recent overnight sound-event session -- `nil` before
        /// format 3.
        let soundEvents: [SoundEvent]?
        /// Explicit per-behaviour answers. Optional so a V3 archive,
        /// which predates them, still decodes -- those import as no
        /// answers at all, which is the honest result rather than a
        /// reconstruction from the positive tags in `journal`.
        let behaviorObservations: [BehaviorObservationRecordExport]?
        var evidenceHistory: [EvidenceLedger.Revision]? = nil
        var personalSetup: PersonalSetup? = nil
        /// The person's own behaviour definitions.
        ///
        /// Their observations already travel in `behaviorObservations`,
        /// which is identifier-keyed and so carries custom rows without
        /// knowing it. The names did not, so a restore produced a history of
        /// answers about signals the app could no longer name. `nil` for any
        /// archive taken before this existed, which imports as no
        /// definitions -- honest, and the observations still restore.
        var customBehaviors: [CustomBehavior]? = nil
        /// Alertness-check sessions. `nil` before format 6, which imports as
        /// no sessions rather than a history of zeros.
        var alertnessSessions: [AlertnessCheck.Session]? = nil

        struct EpisodeRecord: Codable {
            let id: String
            let nightKey: String
            let startDate: Date
            let endDate: Date
            let timezoneIdentifier: String
            /// `SleepEpisodeType.rawValue` -- stored raw rather than as the
            /// enum itself so an episode type added after this backup was
            /// taken still round-trips instead of failing to decode.
            let episodeType: String
            let asleepMinutes: Double
            let timeInBedMinutes: Double
            let sourceName: String?
        }

        /// A `BehaviorObservationRecord` flattened for export.
        ///
        /// A separate value type rather than the `@Model` itself: a
        /// SwiftData model is not a portable archive record, and pinning
        /// the wire format here means a later schema change to the stored
        /// model cannot silently alter what a backup contains.
        struct BehaviorObservationRecordExport: Codable {
            let nightKey: String
            let behaviorIdentifier: String
            /// `BehaviorObservationState.rawValue`.
            let state: String
            /// `BehaviorObservationSource.rawValue`.
            let source: String
            let observedAt: Date
            /// Format 6. Optional keys: absent in an older archive, and
            /// absent on a row with no detail -- never a zero standing in.
            var quantity: Double? = nil
            var unit: String? = nil
            var eventTime: Date? = nil
            var intensity: Double? = nil
        }

        struct JournalRecord: Codable {
            let date: Date
            let tags: [String]
            let note: String?
            /// `MorningFeeling.rawValue`. Optional key -- a format-2 backup
            /// exported before this field existed simply decodes it as `nil`.
            let feeling: Int?
            /// Morning Check-In V2 dimensions, each 1...5. Optional keys --
            /// backups exported before these existed simply decode as `nil`.
            let rested: Int?
            let energy: Int?
            let sleepiness: Int?
            let mood: Int?
            /// `JournalEntry.nightKey`, when the entry had one at export
            /// time. Optional -- older backups, and entries written before
            /// this field existed, decode it as `nil` and fall back to
            /// `date`-based matching on import, same as the live app does
            /// (see `JournalEntry.nightKey`'s doc comment). Carrying it
            /// through matters on a travel day: without it, a restored
            /// entry can silently stop matching the night it was actually
            /// about.
            let nightKey: String?
        }

        struct PreferencesRecord: Codable {
            let age: Int?
            /// `DemographicBaseline.Sex.rawValue`. Optional — older backups decode nil.
            let biologicalSex: String?
            /// kg / m². Optional — older backups decode nil.
            let bodyMassIndex: Double?
            let preferredEngine: String
            let appearance: String
            let bedtimeRemindersEnabled: Bool
            let cycleTrackingEnabled: Bool
            let smartWakeEnabled: Bool
            /// Optional key -- a backup exported before Lifestyle Insights
            /// existed simply decodes it as `nil`, treated as off.
            let lifestyleInsightsEnabled: Bool?
            /// Optional keys -- all three added in format 3, decode as
            /// `nil`/off/automatic on any older backup.
            let wakeAlarmEnabled: Bool?
            let focusSilencesBedtimeNudges: Bool?
            let preferredSleepSourceName: String?
            /// All optional -- added after format 3 shipped, so any earlier
            /// backup simply decodes these as `nil` and the corresponding
            /// preference stays at its default.
            let preferredSleepSourceBundleIdentifier: String?
            let obligationWeekdays: [Int]?
            let isShiftWorkModeEnabled: Bool?
            /// `ShiftWorkMode.rawValue`. Optional -- a backup written before
            /// the mode replaced the Bool decodes as `nil`, and import falls
            /// back to migrating `isShiftWorkModeEnabled` instead, which is
            /// exactly what a fresh install does with the same old value.
            let shiftWorkMode: String?
            let trackedBehaviorTagIdentifiers: [String]?
            /// A currently-running Guided Experiment, if one was active at
            /// export time. All four travel together -- `activeExperimentTag`
            /// is the signal that the others are meaningful at all.
            let activeExperimentTag: String?
            let experimentStartDate: Date?
            let experimentHypothesis: String?
            let experimentPrimaryMetric: String?
            let experimentDirection: String?
            /// How the running trial is laid out, and the seed its block
            /// order was drawn from. Optional and added without a format
            /// bump, the same way `recoveryModeDate` below was: an older
            /// backup decodes them as nil, which restores as a plain
            /// before/after -- true of every trial that existed before
            /// designs did. Both travel because a design without its seed
            /// would have to redraw the order on restore, and a restored
            /// crossover that reshuffles its remaining blocks is exactly what
            /// the seed exists to prevent.
            let experimentDesign: String?
            let experimentDesignSeed: Int?
            /// The date Recovery Mode was turned on, if it was on at export
            /// time. Optional -- added after format 4 shipped, so an earlier
            /// backup decodes it as `nil`. Not a version bump: unlike the
            /// behaviour answers that forced 4, this value is day-scoped and
            /// expires on its own, so a V4 file restoring without it loses
            /// nothing that would still have applied.
            let recoveryModeDate: Date?
            /// Optional -- added without a format bump. An older backup
            /// decodes as `nil` and restores as off, which is the default.
            let morningBriefEnabled: Bool?
        }

        struct WristTemperatureRecord: Codable {
            let date: Date
            let absoluteCelsius: Double
        }

        var wristTemperaturesByDate: [Date: Double] {
            (wristTemperatures ?? []).reduce(into: [:]) { result, record in
                // A hand-edited or older backup may contain duplicate rows.
                // Last value wins; imported user data must never crash the app.
                result[record.date] = record.absoluteCelsius
            }
        }
    }

    // MARK: - Build

    @MainActor
    static func archive(
        nights: [SleepNightFeatures],
        journal: [JournalEntry],
        naps: [NapStore.Nap],
        goalMinutes: Double,
        preferences: UserPreferences,
        snoreSummaries: [SnoreStore.NightSummary],
        wristTemperatures: [(date: Date, absoluteCelsius: Double)],
        episodes: [Archive.EpisodeRecord] = [],
        experiments: [SleepExperimentStore.Outcome] = [],
        soundEvents: [SoundEvent] = [],
        behaviorObservations: [Archive.BehaviorObservationRecordExport] = [],
        evidenceHistory: [EvidenceLedger.Revision] = [],
        personalSetup: PersonalSetup? = nil,
        customBehaviors: [CustomBehavior] = [],
        alertnessSessions: [AlertnessCheck.Session] = []
    ) -> Archive {
        Archive(
            formatVersion: formatVersion,
            exportedAt: .now,
            goalMinutes: goalMinutes,
            nights: nights,
            journal: journal.map {
                Archive.JournalRecord(
                    date: $0.date, tags: $0.tagIdentifiers, note: $0.note, feeling: $0.feelingRaw,
                    rested: $0.restedRaw, energy: $0.energyRaw, sleepiness: $0.sleepinessRaw, mood: $0.moodRaw,
                    nightKey: $0.nightKey
                )
            },
            naps: naps,
            preferences: Archive.PreferencesRecord(
                age: preferences.age,
                biologicalSex: preferences.biologicalSex == .unspecified ? nil : preferences.biologicalSex.rawValue,
                bodyMassIndex: preferences.bodyMassIndex,
                preferredEngine: preferences.preferredEngine.rawValue,
                appearance: preferences.appearance.rawValue,
                bedtimeRemindersEnabled: preferences.bedtimeRemindersEnabled,
                cycleTrackingEnabled: preferences.cycleTrackingEnabled,
                smartWakeEnabled: preferences.smartWakeEnabled,
                lifestyleInsightsEnabled: preferences.lifestyleInsightsEnabled,
                wakeAlarmEnabled: preferences.wakeAlarmEnabled,
                focusSilencesBedtimeNudges: preferences.focusSilencesBedtimeNudges,
                preferredSleepSourceName: preferences.preferredSleepSourceName,
                preferredSleepSourceBundleIdentifier: preferences.preferredSleepSourceBundleIdentifier,
                obligationWeekdays: Array(preferences.obligationWeekdays),
                isShiftWorkModeEnabled: preferences.isShiftWorkModeEnabled,
                shiftWorkMode: preferences.shiftWorkMode.rawValue,
                trackedBehaviorTagIdentifiers: preferences.trackedBehaviorTagIdentifiers.map(Array.init),
                activeExperimentTag: preferences.activeExperimentTag?.rawValue,
                experimentStartDate: preferences.experimentStartDate,
                experimentHypothesis: preferences.experimentHypothesis,
                experimentPrimaryMetric: preferences.experimentPrimaryMetric?.rawValue,
                experimentDirection: preferences.experimentDirection?.rawValue,
                experimentDesign: preferences.experimentDesign?.rawValue,
                experimentDesignSeed: preferences.experimentDesignSeed
                    .map { Int(bitPattern: UInt(truncatingIfNeeded: $0)) },
                recoveryModeDate: preferences.recoveryModeDateForBackup,
                morningBriefEnabled: preferences.morningBriefEnabled
            ),
            snoreSummaries: snoreSummaries,
            wristTemperatures: wristTemperatures.map {
                Archive.WristTemperatureRecord(
                    date: $0.date,
                    absoluteCelsius: $0.absoluteCelsius
                )
            },
            episodes: episodes,
            experiments: experiments,
            soundEvents: soundEvents,
            behaviorObservations: behaviorObservations,
            evidenceHistory: evidenceHistory,
            personalSetup: personalSetup,
            customBehaviors: customBehaviors,
            alertnessSessions: alertnessSessions
        )
    }

    static func jsonData(_ archive: Archive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// One row per night, with a header. Dates are ISO-8601 so spreadsheets
    /// parse them without a locale fight. `date` is the wake day in the
    /// night's own timezone (the trailing `timezone` column says which);
    /// `bedtime`/`wake_time` stay as UTC instants.
    static func csv(nights: [SleepNightFeatures]) -> String {
        let header = [
            "date", "bedtime", "wake_time", "time_in_bed_min", "time_asleep_min",
            "efficiency_pct", "deep_min", "rem_min", "core_min", "unspecified_min",
            "awake_min", "wake_count", "latency_min", "avg_hr", "min_hr", "resting_hr", "hrv_ms",
            "respiratory_rate", "spo2_pct", "wrist_temp_delta_c", "source", "timezone"
        ].joined(separator: ",")

        let formatter = ISO8601DateFormatter()

        let rows = nights.sorted { $0.date < $1.date }.map { night -> String in
            [
                ISO8601DateFormatter.dayString(for: night.date, timeZone: night.timeZone),
                formatter.string(from: night.bedtime),
                formatter.string(from: night.wakeTime),
                num(night.timeInBedMinutes), num(night.timeAsleepMinutes),
                num(night.sleepEfficiencyPercent), num(night.deepMinutes),
                num(night.remMinutes), num(night.coreMinutes),
                num(night.unspecifiedAsleepMinutes), num(night.awakeMinutes),
                "\(night.wakeCount)",
                num(night.sleepLatencyMinutes), num(night.avgHeartRate),
                num(night.minHeartRate), num(night.restingHeartRate), num(night.avgHRV),
                num(night.avgRespiratoryRate), num(night.avgSpO2),
                num(night.wristTempDeltaC),
                escape(night.sourceName ?? ""),
                escape(night.timeZoneIdentifier)
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    private static func num(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }

    /// RFC 4180 escaping. Source names come from device names, which users set
    /// to things like `Ali's iPhone, work` more often than you'd hope.
    private static func escape(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else { return text }
        return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Files

    /// Writes to the caches directory and returns the URL for `ShareLink`.
    ///
    /// Caches rather than Documents: these are throwaway artefacts of a share,
    /// and the system can reclaim them. Leaving copies of someone's health data
    /// in Documents forever would be careless.
    static func writeTemporary(_ data: Data, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func defaultFilename(extension ext: String) -> String {
        "zoon-export-\(ISO8601DateFormatter.dayString(for: .now, timeZone: .current)).\(ext)"
    }

    /// Every filename prefix Zoon writes into the temporary directory: the
    /// archive/CSV exports here, the clinician PDFs named by
    /// `ClinicianReportGenerator.filename`, the Weekly Wrapped image and the
    /// last-night share card. `clearTemporaryExports` removes all of them,
    /// not just the first.
    private static let temporaryExportPrefixes = [
        "zoon-export-", "Sleep_Report_", "zoon-week-", "zoon-last-night"
    ]

    /// Removes health-data export artefacts still owned by Zoon. Copies the
    /// user deliberately saved through the share sheet live outside this
    /// sandbox and remain under their control.
    @discardableResult
    static func clearTemporaryExports() -> Bool {
        let directory = FileManager.default.temporaryDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return false }

        var succeeded = true
        for url in urls where temporaryExportPrefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }

    // MARK: - Import

    enum ImportError: LocalizedError {
        case unreadable
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "That file isn't a Zoon export, or it's damaged."
            case let .unsupportedVersion(version):
                "That export was made by a newer version of Zoon (format \(version))."
            }
        }
    }

    /// Larger than any real archive by an order of magnitude: ten years of
    /// nights with every optional field is a few megabytes. The cap is
    /// against a file that would exhaust memory decoding, not a quota.
    static let maximumArchiveBytes = 64 * 1024 * 1024

    static func decode(_ data: Data) throws -> Archive {
        guard data.count <= maximumArchiveBytes else { throw ImportError.unreadable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(Archive.self, from: data) else {
            throw ImportError.unreadable
        }
        guard archive.formatVersion <= formatVersion else {
            throw ImportError.unsupportedVersion(archive.formatVersion)
        }
        guard archive.formatVersion > 0, validationFailure(archive) == nil else {
            throw ImportError.unreadable
        }
        return archive
    }

    /// Why an archive cannot be imported, or `nil` when it can.
    ///
    /// Run on the whole file **before any write**. Checking a handful of
    /// fields let through reversed episode intervals -- which later reach
    /// `DateInterval(start:end:)`, a trap -- and finite values large enough
    /// to overflow an `Int` conversion on screen. An archive either passes
    /// every rule or none of it is imported: a partial restore of a file
    /// that is wrong somewhere is a restore of data nobody can vouch for.
    ///
    /// Returned as a reason rather than a Bool so a test can say which rule
    /// caught which mutation.
    static func validationFailure(_ archive: Archive) -> String? {
        let day: Double = 24 * 60
        func minutes(_ value: Double) -> Bool { value.isFinite && value >= 0 && value <= day }
        func text(_ value: String?, _ limit: Int) -> Bool { (value?.count ?? 0) <= limit }

        guard (1...formatVersion).contains(archive.formatVersion) else { return "version" }
        guard archive.goalMinutes.isFinite, (60...day).contains(archive.goalMinutes) else { return "goal" }

        // Counts: far beyond any real history, well short of exhausting memory.
        guard archive.nights.count <= 20_000,
              archive.journal.count <= 20_000,
              archive.naps.count <= 20_000,
              (archive.episodes?.count ?? 0) <= 50_000,
              (archive.snoreSummaries?.count ?? 0) <= 1_000,
              (archive.soundEvents?.count ?? 0) <= 10_000,
              (archive.behaviorObservations?.count ?? 0) <= 200_000,
              (archive.evidenceHistory?.count ?? 0) <= 50_000,
              (archive.wristTemperatures?.count ?? 0) <= 20_000,
              (archive.customBehaviors?.count ?? 0) <= 1_000,
              (archive.alertnessSessions?.count ?? 0) <= 10_000
        else { return "count" }

        var nightDates = Set<Date>()
        for night in archive.nights {
            guard night.bedtime < night.wakeTime,
                  night.wakeTime.timeIntervalSince(night.bedtime) <= day * 60,
                  minutes(night.timeInBedMinutes), minutes(night.timeAsleepMinutes),
                  minutes(night.coreMinutes), minutes(night.deepMinutes),
                  minutes(night.remMinutes), minutes(night.unspecifiedAsleepMinutes),
                  minutes(night.awakeMinutes),
                  (0...500).contains(night.wakeCount)
            else { return "night" }
            guard nightDates.insert(night.date).inserted else { return "duplicate night" }
        }

        for nap in archive.naps {
            guard nap.start < nap.end, nap.end.timeIntervalSince(nap.start) <= 12 * 3600 else { return "nap" }
        }

        var episodeIDs = Set<String>()
        for episode in archive.episodes ?? [] {
            guard episode.startDate < episode.endDate,
                  episode.endDate.timeIntervalSince(episode.startDate) <= day * 60,
                  minutes(episode.asleepMinutes), minutes(episode.timeInBedMinutes),
                  !episode.nightKey.isEmpty, text(episode.nightKey, 64),
                  TimeZone(identifier: episode.timezoneIdentifier) != nil,
                  text(episode.sourceName, 256), text(episode.episodeType, 64)
            else { return "episode" }
            guard episodeIDs.insert(episode.id).inserted else { return "duplicate episode" }
        }

        let rating = 1...5
        for entry in archive.journal {
            guard text(entry.note, 10_000), entry.tags.count <= 200,
                  entry.tags.allSatisfy({ text($0, 100) }),
                  [entry.rested, entry.energy, entry.sleepiness, entry.mood]
                    .allSatisfy({ $0.map(rating.contains) ?? true }),
                  text(entry.nightKey, 64)
            else { return "journal" }
        }

        for summary in archive.snoreSummaries ?? [] {
            guard minutes(summary.monitoredMinutes), minutes(summary.snoreMinutes),
                  summary.snoreMinutes <= summary.monitoredMinutes + 0.5
            else { return "snore" }
        }

        for record in archive.wristTemperatures ?? [] {
            guard record.absoluteCelsius.isFinite, (25...45).contains(record.absoluteCelsius) else {
                return "temperature"
            }
        }

        var observationIDs = Set<String>()
        for observation in archive.behaviorObservations ?? [] {
            guard !observation.nightKey.isEmpty, text(observation.nightKey, 64),
                  !observation.behaviorIdentifier.isEmpty, text(observation.behaviorIdentifier, 200),
                  text(observation.state, 32), text(observation.source, 32),
                  observation.quantity.map({ $0.isFinite && $0 >= 0 && $0 <= 100_000 }) ?? true,
                  observation.intensity.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                  text(observation.unit, 32)
            else { return "observation" }
            let identity = BehaviorObservationRecord.identity(
                nightKey: observation.nightKey, behaviorIdentifier: observation.behaviorIdentifier
            )
            guard observationIDs.insert(identity).inserted else { return "duplicate observation" }
        }

        for event in archive.soundEvents ?? [] {
            guard event.confidence.isFinite, (0...1).contains(event.confidence),
                  text(event.identifier, 128)
            else { return "sound event" }
        }

        var sessionIDs = Set<UUID>()
        for session in archive.alertnessSessions ?? [] {
            guard AlertnessCheckStore.isPlausible(session) else { return "alertness" }
            guard sessionIDs.insert(session.id).inserted else { return "duplicate alertness" }
        }

        guard archive.personalSetup?.isValid != false else { return "setup" }
        return nil
    }
}

/// A `FileDocument` wrapper so `ShareLink` and `.fileExporter` can carry the
/// archive without a temp file dance at every call site.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    let data: Data
    let type: UTType

    init(data: Data, type: UTType) {
        self.data = data
        self.type = type
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw DataExporter.ImportError.unreadable
        }
        self.data = contents
        self.type = .json
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

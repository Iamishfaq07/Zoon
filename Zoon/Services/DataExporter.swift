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
    static let formatVersion = 4

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
            /// The date Recovery Mode was turned on, if it was on at export
            /// time. Optional -- added after format 4 shipped, so an earlier
            /// backup decodes it as `nil`. Not a version bump: unlike the
            /// behaviour answers that forced 4, this value is day-scoped and
            /// expires on its own, so a V4 file restoring without it loses
            /// nothing that would still have applied.
            let recoveryModeDate: Date?
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
        behaviorObservations: [Archive.BehaviorObservationRecordExport] = []
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
                recoveryModeDate: preferences.recoveryModeDateForBackup
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
            behaviorObservations: behaviorObservations
        )
    }

    static func jsonData(_ archive: Archive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// One row per night, with a header. Dates are ISO-8601 so spreadsheets
    /// parse them without a locale fight.
    static func csv(nights: [SleepNightFeatures]) -> String {
        let header = [
            "date", "bedtime", "wake_time", "time_in_bed_min", "time_asleep_min",
            "efficiency_pct", "deep_min", "rem_min", "core_min", "unspecified_min",
            "awake_min", "wake_count", "latency_min", "avg_hr", "min_hr", "resting_hr", "hrv_ms",
            "respiratory_rate", "spo2_pct", "wrist_temp_delta_c", "source"
        ].joined(separator: ",")

        let formatter = ISO8601DateFormatter()

        let rows = nights.sorted { $0.date < $1.date }.map { night -> String in
            [
                ISO8601DateFormatter.dayOnly.string(from: night.date),
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
                escape(night.sourceName ?? "")
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
        "zoon-export-\(ISO8601DateFormatter.dayOnly.string(from: .now)).\(ext)"
    }

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
        for url in urls where url.lastPathComponent.hasPrefix("zoon-export-") {
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

    static func decode(_ data: Data) throws -> Archive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(Archive.self, from: data) else {
            throw ImportError.unreadable
        }
        guard archive.formatVersion <= formatVersion else {
            throw ImportError.unsupportedVersion(archive.formatVersion)
        }
        return archive
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

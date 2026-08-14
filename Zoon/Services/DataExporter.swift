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
    static let formatVersion = 2

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
        }

        struct PreferencesRecord: Codable {
            let age: Int?
            let preferredEngine: String
            let appearance: String
            let bedtimeRemindersEnabled: Bool
            let cycleTrackingEnabled: Bool
            let smartWakeEnabled: Bool
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
        wristTemperatures: [(date: Date, absoluteCelsius: Double)]
    ) -> Archive {
        Archive(
            formatVersion: formatVersion,
            exportedAt: .now,
            goalMinutes: goalMinutes,
            nights: nights,
            journal: journal.map {
                Archive.JournalRecord(
                    date: $0.date, tags: $0.tagIdentifiers, note: $0.note, feeling: $0.feelingRaw,
                    rested: $0.restedRaw, energy: $0.energyRaw, sleepiness: $0.sleepinessRaw, mood: $0.moodRaw
                )
            },
            naps: naps,
            preferences: Archive.PreferencesRecord(
                age: preferences.age,
                preferredEngine: preferences.preferredEngine.rawValue,
                appearance: preferences.appearance.rawValue,
                bedtimeRemindersEnabled: preferences.bedtimeRemindersEnabled,
                cycleTrackingEnabled: preferences.cycleTrackingEnabled,
                smartWakeEnabled: preferences.smartWakeEnabled
            ),
            snoreSummaries: snoreSummaries,
            wristTemperatures: wristTemperatures.map {
                Archive.WristTemperatureRecord(
                    date: $0.date,
                    absoluteCelsius: $0.absoluteCelsius
                )
            }
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

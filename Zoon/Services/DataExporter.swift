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
    static let formatVersion = 1

    struct Archive: Codable {
        let formatVersion: Int
        let exportedAt: Date
        let goalMinutes: Double
        let nights: [SleepNightFeatures]
        let journal: [JournalRecord]
        let naps: [NapStore.Nap]

        struct JournalRecord: Codable {
            let date: Date
            let tags: [String]
            let note: String?
        }
    }

    // MARK: - Build

    static func archive(
        nights: [SleepNightFeatures],
        journal: [JournalEntry],
        naps: [NapStore.Nap],
        goalMinutes: Double
    ) -> Archive {
        Archive(
            formatVersion: formatVersion,
            exportedAt: .now,
            goalMinutes: goalMinutes,
            nights: nights,
            journal: journal.map {
                Archive.JournalRecord(date: $0.date, tags: $0.tagIdentifiers, note: $0.note)
            },
            naps: naps
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
            "awake_min", "wake_count", "latency_min", "avg_hr", "min_hr", "hrv_ms",
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
                num(night.minHeartRate), num(night.avgHRV),
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
        try data.write(to: url, options: .atomic)
        return url
    }

    static func defaultFilename(extension ext: String) -> String {
        "zoon-export-\(ISO8601DateFormatter.dayOnly.string(from: .now)).\(ext)"
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

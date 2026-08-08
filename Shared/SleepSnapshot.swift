import Foundation
import os

/// The payload the app hands to the widget.
///
/// The widget deliberately does **not** open the SwiftData store. Two reasons:
/// a widget extension has a tight memory budget and no business running the
/// HealthKit pipeline, and keeping the contract to one small immutable value
/// means a schema migration in the app can never crash the widget.
struct SleepSnapshot: Codable, Hashable, Sendable {

    let date: Date
    let score: Int
    let scoreBand: String
    let timeAsleepMinutes: Double
    /// Positive = under-slept, in minutes, over the trailing 14 days.
    let sleepDebtMinutes: Double
    let goalMinutes: Double
    let insightSummary: String
    let generatedAt: Date

    /// Added after the first release. Defaulted so a snapshot written by an
    /// older build still decodes — the widget must never fail to render because
    /// the app hasn't been relaunched since an update.
    var recoveryPercent: Int = 0
    var bodyBattery: Int = 0
    var strain: Double = 0
    var sleepPerformance: Double = 0

    var isMock: Bool = false

    /// Sleep debt expressed in hours, which is how the widget phrases it.
    var sleepDebtHours: Double { sleepDebtMinutes / 60 }

    /// "Bank balance" framing: debt is a negative balance the user is carrying.
    /// Zero debt reads as "even", never as a positive balance — you cannot bank
    /// surplus sleep, and implying otherwise would be a lie the physiology
    /// doesn't support.
    var balanceLabel: String {
        if sleepDebtMinutes < 15 { return "Even" }
        let hours = sleepDebtHours
        return hours < 10
            ? String(format: "−%.1fh", hours)
            : String(format: "−%.0fh", hours)
    }
}

extension SleepSnapshot {

    init(
        features: SleepNightFeatures,
        score: SleepScore,
        insight: SleepInsight,
        goalMinutes: Double,
        recoveryPercent: Int = 0,
        bodyBattery: Int = 0,
        strain: Double = 0,
        sleepPerformance: Double = 0
    ) {
        self.date = features.date
        self.score = score.value
        self.scoreBand = score.band.label
        self.timeAsleepMinutes = features.timeAsleepMinutes
        self.sleepDebtMinutes = features.sleepDebtMinutes14Day ?? 0
        self.goalMinutes = goalMinutes
        self.insightSummary = insight.summary
        self.generatedAt = .now
        self.recoveryPercent = recoveryPercent
        self.bodyBattery = bodyBattery
        self.strain = strain
        self.sleepPerformance = sleepPerformance
        self.isMock = features.isMock
    }
}

// MARK: - Shared container

/// Resolves where the app and widget exchange data.
///
/// **The App Group is optional by design.** Configuring one requires a paid
/// developer account and a matching identifier on both targets; demanding that
/// before the project will build would make "clone and run" impossible. So:
///
/// - App Group configured → snapshot lands in the shared container, widget shows
///   live data.
/// - Not configured → snapshot lands in the app's own Documents directory. The
///   app works fully; the widget falls back to sample data and says so.
///
/// See SETUP.md → "Enable live widget data".
enum AppGroup {

    /// Change this to your own App Group ID if you configure one, and set the
    /// same string in the App Groups capability on **both** targets.
    static let identifier = "group.com.zoon.sleep"

    private static let logger = Logger(subsystem: "com.zoon.sleep", category: "AppGroup")

    /// The shared container URL, or `nil` when no App Group is configured.
    ///
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil`
    /// rather than throwing when the entitlement is absent, which is exactly the
    /// signal we want.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isConfigured: Bool { containerURL != nil }
}

/// Reads and writes the widget snapshot as a single small JSON file.
///
/// A file rather than `UserDefaults` because the widget process may read while
/// the app writes; an atomic file replace gives us a clean all-or-nothing update
/// with no partially-decoded state.
enum SnapshotStore {

    private static let filename = "widget-snapshot.json"
    private static let logger = Logger(subsystem: "com.zoon.sleep", category: "SnapshotStore")

    /// Shared container when available, else the app's Documents directory.
    private static var directory: URL? {
        AppGroup.containerURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private static var fileURL: URL? {
        directory?.appendingPathComponent(filename)
    }

    static func write(_ snapshot: SleepSnapshot) {
        guard let fileURL else {
            logger.error("No writable directory for snapshot")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            // .atomic so a widget read can never observe a half-written file.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Snapshot write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns the last written snapshot, or `nil` if the app has never run,
    /// or if no App Group is configured (the widget cannot see the app's
    /// Documents directory).
    static func read() -> SleepSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SleepSnapshot.self, from: data)
    }
}

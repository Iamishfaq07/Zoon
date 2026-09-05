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

    /// Added after the first release, so a snapshot written by an older build
    /// must still decode — the widget must never fail to render because the
    /// app hasn't been relaunched since an update.
    ///
    /// The default alone does **not** achieve that: Swift's synthesized
    /// `Decodable` throws on a missing key regardless of the default. The
    /// custom `init(from:)` below is what makes it true, and every field
    /// added here needs a matching `decodeIfPresent` line there.
    var recoveryPercent: Int = 0
    var bodyBattery: Int = 0
    var strain: Double = 0
    var sleepPerformance: Double = 0

    /// Added alongside the Sleep Intelligence redesign. Defaulted to 0/"" so a
    /// snapshot written by a build that predates this field still decodes —
    /// the Watch app treats 0 with an empty band the same way it already
    /// treats a missing recovery reading: as "nothing to show yet", not zero.
    var sleepIntelligencePercent: Int = 0
    var sleepIntelligenceBand: String = ""

    var isMock: Bool = false

    // MARK: - Badges
    //
    // Defaulted so an older snapshot already on disk still decodes. The widget
    // and the app are separate processes updated together, but a snapshot
    // written before an app update is read after it, and a decode failure
    // there would blank every widget on the home screen.

    /// Hardest badge earned, for the badge widget.
    var badgeTitle: String = ""
    var badgeSymbol: String = "hexagon.fill"
    var badgeTier: Int = 0
    var badgesUnlocked: Int = 0
    var badgesTotal: Int = 0
    /// Closest locked badge, and how far along it is.
    var nextBadgeTitle: String = ""
    var nextBadgeProgress: Double = 0

    /// `HealthRadar.Severity.label` as of the last publish -- "Nothing
    /// unusual", "Worth watching", or "Several signals moving". Defaulted
    /// for the same reason every other field added after the first release
    /// is: an older snapshot on disk still decodes, and the Watch app
    /// treats the default the same as a genuinely clear reading rather than
    /// failing to render.
    var bodySignalsLabel: String = "Nothing unusual"

    /// Mirrors `UserPreferences.isShiftWorkModeEnabled` as of the last
    /// publish. The widget extension never reads `UserPreferences` itself
    /// (it's a separate process with no HealthKit pipeline -- see this
    /// type's own doc comment), so without this the "Last Night" label
    /// couldn't follow the toggle at all. Defaulted `false` for the same
    /// reason every field added after the first release is: an older
    /// snapshot on disk still decodes, and false is the setting's own
    /// default besides.
    var isShiftWorkModeEnabled: Bool = false

    /// Tonight's `SleepAutopilot` target, pre-formatted as "23:40 - 07:00",
    /// and the one-line reason underneath it.
    ///
    /// Formatted on the phone rather than published as raw minutes for two
    /// reasons. The autopilot works on a signed minutes-from-midnight scale
    /// that has to be folded back onto a clock face before display, and
    /// re-implementing that fold in the watch and widget targets is three
    /// copies of an off-by-a-day bug waiting to happen. The engine also
    /// needs the whole night history to run at all, which neither extension
    /// has -- the same reason badges are evaluated on the phone.
    ///
    /// Empty when there is too little history for a plan. Defaulted for the
    /// same reason every field added after the first release is: an older
    /// snapshot on disk still decodes.
    var tonightTargetLabel: String = ""
    var tonightTargetNote: String = ""

    /// The tightest `UncertaintyForecast` range, phrased for a small screen:
    /// where recent nights actually landed.
    ///
    /// Despite the name, this is not a forecast and must never be presented
    /// as one -- the engine does not condition on context and has never been
    /// calibrated against what followed. The name is kept only because it is
    /// the Codable key: renaming it would decode as empty on every snapshot
    /// already written, blanking the widget until the next publish.
    var tomorrowRangeLabel: String = ""

    /// Whether the autopilot is holding rather than asking for a change.
    /// Carried so the watch can say so plainly instead of inferring "no
    /// change" from an absent shift, which would read the same as "no plan".
    var isTonightTargetHolding: Bool = false

    /// The single strongest claim Zoon holds, phrased for a glance.
    ///
    /// Compiled phone-side by `EvidenceNotebook`, which needs the journal,
    /// the experiment store and the whole night history -- none of which an
    /// extension has. Empty when nothing clears the bar below.
    var headlineFindingText: String = ""

    /// Which tier that claim came from -- "You tested this", "Association".
    ///
    /// Carried rather than derived, and rendered beside the claim rather
    /// than behind a tap. The whole point of the evidence hierarchy is that
    /// a claim without its strength is a different, stronger claim; a glance
    /// surface is where that distinction is most likely to be dropped and
    /// least likely to be recovered by the reader.
    var headlineFindingStrength: String = ""

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

    /// Decoding that actually honours the defaults above.
    ///
    /// Swift's *synthesized* `Decodable` ignores property default values: a
    /// missing key throws `keyNotFound` whether or not the property has a
    /// default, because defaults feed the memberwise initializer, not
    /// `init(from:)`. So every "defaulted so an older payload still decodes"
    /// comment on this type described behaviour it did not have -- an older
    /// snapshot threw, `SnapshotStore.read()` swallowed it with `try?`, and
    /// every widget on the home screen quietly fell back to sample data until
    /// the app was next launched and rewrote the file. Exactly the failure
    /// the defaults were there to prevent.
    ///
    /// `decodeIfPresent` for each post-release field is what makes the
    /// contract real. New fields must be added here too, which the
    /// compatibility tests enforce.
    ///
    /// Declared in an extension, not the struct body: an initializer in the
    /// body would suppress the memberwise initializer that the rest of the
    /// codebase (and the tests) construct snapshots with.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Present since the first release; a payload without these is not a
        // Zoon snapshot at all, so these stay strict.
        date = try container.decode(Date.self, forKey: .date)
        score = try container.decode(Int.self, forKey: .score)
        scoreBand = try container.decode(String.self, forKey: .scoreBand)
        timeAsleepMinutes = try container.decode(Double.self, forKey: .timeAsleepMinutes)
        sleepDebtMinutes = try container.decode(Double.self, forKey: .sleepDebtMinutes)
        goalMinutes = try container.decode(Double.self, forKey: .goalMinutes)
        insightSummary = try container.decode(String.self, forKey: .insightSummary)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)

        // Added later. Each falls back to the same default declared above.
        recoveryPercent = try container.decodeIfPresent(Int.self, forKey: .recoveryPercent) ?? 0
        bodyBattery = try container.decodeIfPresent(Int.self, forKey: .bodyBattery) ?? 0
        strain = try container.decodeIfPresent(Double.self, forKey: .strain) ?? 0
        sleepPerformance = try container.decodeIfPresent(Double.self, forKey: .sleepPerformance) ?? 0
        sleepIntelligencePercent = try container.decodeIfPresent(Int.self, forKey: .sleepIntelligencePercent) ?? 0
        sleepIntelligenceBand = try container.decodeIfPresent(String.self, forKey: .sleepIntelligenceBand) ?? ""
        isMock = try container.decodeIfPresent(Bool.self, forKey: .isMock) ?? false
        badgeTitle = try container.decodeIfPresent(String.self, forKey: .badgeTitle) ?? ""
        badgeSymbol = try container.decodeIfPresent(String.self, forKey: .badgeSymbol) ?? "hexagon.fill"
        badgeTier = try container.decodeIfPresent(Int.self, forKey: .badgeTier) ?? 0
        badgesUnlocked = try container.decodeIfPresent(Int.self, forKey: .badgesUnlocked) ?? 0
        badgesTotal = try container.decodeIfPresent(Int.self, forKey: .badgesTotal) ?? 0
        nextBadgeTitle = try container.decodeIfPresent(String.self, forKey: .nextBadgeTitle) ?? ""
        nextBadgeProgress = try container.decodeIfPresent(Double.self, forKey: .nextBadgeProgress) ?? 0
        bodySignalsLabel = try container.decodeIfPresent(String.self, forKey: .bodySignalsLabel) ?? "Nothing unusual"
        isShiftWorkModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isShiftWorkModeEnabled) ?? false

        // Tonight's plan and tomorrow's range. Missing here until now, which
        // is why every surface that reads them has only ever shown its
        // waiting copy: `encode(to:)` is synthesised and writes all of them,
        // so the phone published the values and this decoder dropped them on
        // the floor. Silent, because each one falls back to a default that
        // reads as "no plan yet" rather than failing.
        tonightTargetLabel = try container.decodeIfPresent(String.self, forKey: .tonightTargetLabel) ?? ""
        tonightTargetNote = try container.decodeIfPresent(String.self, forKey: .tonightTargetNote) ?? ""
        tomorrowRangeLabel = try container.decodeIfPresent(String.self, forKey: .tomorrowRangeLabel) ?? ""
        isTonightTargetHolding = try container.decodeIfPresent(Bool.self, forKey: .isTonightTargetHolding) ?? false

        // The strongest claim, for the watch. Same story.
        headlineFindingText = try container.decodeIfPresent(String.self, forKey: .headlineFindingText) ?? ""
        headlineFindingStrength = try container.decodeIfPresent(String.self, forKey: .headlineFindingStrength) ?? ""
    }

    init(
        features: SleepNightFeatures,
        score: SleepScore,
        insight: SleepInsight,
        goalMinutes: Double,
        recoveryPercent: Int = 0,
        bodyBattery: Int = 0,
        strain: Double = 0,
        sleepPerformance: Double = 0,
        sleepIntelligencePercent: Int = 0,
        sleepIntelligenceBand: String = "",
        isShiftWorkModeEnabled: Bool = false
    ) {
        self.date = features.date
        self.score = score.value
        self.scoreBand = score.band.label
        self.timeAsleepMinutes = features.timeAsleepMinutes
        self.sleepDebtMinutes = features.sleepDebtMinutes ?? 0
        self.goalMinutes = goalMinutes
        self.insightSummary = insight.summary
        self.generatedAt = .now
        self.recoveryPercent = recoveryPercent
        self.bodyBattery = bodyBattery
        self.strain = strain
        self.sleepPerformance = sleepPerformance
        self.sleepIntelligencePercent = sleepIntelligencePercent
        self.sleepIntelligenceBand = sleepIntelligenceBand
        self.isMock = features.isMock
        self.isShiftWorkModeEnabled = isShiftWorkModeEnabled
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
    static let identifier = "group.com.zoon.sleep.shared"

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

    /// Removes every phone-side copy of the snapshot.
    ///
    /// Both locations matter during App Group setup: an older build may have
    /// written to Documents before the shared entitlement became available.
    /// Leaving that fallback file behind would violate the promise made by the
    /// app's Delete Everything action even if no extension can currently see it.
    @discardableResult
    static func clear() -> Bool {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
        let directories = [AppGroup.containerURL, documents].compactMap { $0 }
        var succeeded = true

        for directory in Set(directories) {
            let candidate = directory.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            do {
                try FileManager.default.removeItem(at: candidate)
            } catch {
                succeeded = false
                logger.error("Snapshot deletion failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        return succeeded
    }
}

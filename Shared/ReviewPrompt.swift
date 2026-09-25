import Foundation

/// When Zoon may ask for an App Store rating.
///
/// Rarely, and at a good moment: only once there are two weeks of nights
/// (enough to have seen what the app does), only the morning after a night
/// that met the person's sleep need, and at most once per app version.
/// StoreKit adds its own cap of three prompts a year and may show nothing;
/// this decides only whether to ask, never how often the sheet appears.
enum ReviewPrompt {

    static let minimumNights = 14
    /// A night within this of its need counts as having met it -- the same
    /// tolerance `MoodSleepLink` uses.
    static let metNeedToleranceMinutes: Double = 15

    private static let lastVersionKey = "zoon.reviewPrompt.lastVersion"

    static func shouldAsk(
        nightsRecorded: Int,
        lastNight: SleepNightFeatures,
        currentVersion: String,
        lastAskedVersion: String?
    ) -> Bool {
        guard nightsRecorded >= minimumNights,
              !currentVersion.isEmpty,
              lastAskedVersion != currentVersion,
              let need = lastNight.sleepNeedBaselineMinutes, need > 0 else { return false }
        return need - lastNight.timeAsleepMinutes <= metNeedToleranceMinutes
    }

    static var lastAskedVersion: String? {
        get { UserDefaults.standard.string(forKey: lastVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastVersionKey) }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

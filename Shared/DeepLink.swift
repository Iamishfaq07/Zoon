import Foundation

/// Where a Control Center button wants the app to land.
///
/// An intent running in the widget extension and the app that gets launched are
/// **separate processes**, so this can't be an in-memory hop — it's written to
/// shared storage by the extension and read once by the app on activation.
///
/// Falls back to `UserDefaults.standard` when no App Group is configured, which
/// means the two processes can't see each other and the deep link is silently
/// dropped. The control still launches the app, just to the default tab. That's
/// an acceptable degradation for something that is optional by design; see
/// SETUP.md → "Enable live widget data".
enum DeepLink {

    /// Where the app should land.
    ///
    /// The first two are set by Control Center intents. The rest exist so
    /// screenshot capture can reach screens that are only reachable by tapping
    /// — a UI-test target would be the textbook answer, but that means a third
    /// target in the project file, which is the part of this repo that has
    /// broken most often, and this mechanism already works.
    enum Destination: String, Sendable, Hashable, CaseIterable {
        case soundscapes
        case nap
        case sleepDetail
        case breathing
        case snoreCheck
        case report
        case settings
        case badges
        case journal

        /// Which tab owns this screen.
        var tab: String {
            switch self {
            case .soundscapes, .nap, .sleepDetail, .breathing, .snoreCheck: "sleep"
            case .report, .settings, .badges: "more"
            case .journal: "journal"
            }
        }
    }

    private static let key = "zoon.deeplink.pending"

    private static var defaults: UserDefaults {
        AppGroup.containerURL != nil
            ? (UserDefaults(suiteName: AppGroup.identifier) ?? .standard)
            : .standard
    }

    /// Set by an intent, read once by the app.
    static var pending: Destination? {
        get {
            guard let raw = defaults.string(forKey: key) else { return nil }
            return Destination(rawValue: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Reads and clears in one step.
    ///
    /// Consuming rather than just reading matters: a destination left behind
    /// would re-navigate on every subsequent launch, which reads as the app
    /// being stuck on a screen you didn't ask for.
    static func consume() -> Destination? {
        let value = pending
        pending = nil
        return value
    }

    /// Clears both possible stores so changing App Group configuration cannot
    /// resurrect a destination written by an older build.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults(suiteName: AppGroup.identifier)?.removeObject(forKey: key)
    }
}

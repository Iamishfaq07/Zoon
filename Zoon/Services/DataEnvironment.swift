import Foundation

/// Which world the app is reading from: the wearer's real Health data, or the
/// bundled sample dataset.
///
/// This exists because the decision is subtle and was previously re-derived at
/// seven call sites in `SleepDataCoordinator`, each spelling out the same
/// compound condition by hand:
///
/// ```swift
/// guard !LaunchOptions.isDemo, HealthKitManager.isHealthDataAvailable else { ... }
/// ```
///
/// Two things made that fragile enough to be worth naming once:
///
/// - **Order matters, and not obviously.** The demo flag has to be checked
///   *before* health-data availability, because the Simulator genuinely does
///   have a Health store — `isHealthDataAvailable()` returns `true` there — so
///   an availability-first check silently fails to catch a demo launch. That
///   trap was documented in a comment at one call site and simply had to be
///   remembered at the other six.
///
/// - **Every site must agree, forever.** `refresh()` runs again on every
///   foreground activation, so a single site that resolved this differently
///   would produce a demo session that quietly swapped to live data partway
///   through — worse than one that never started. Keeping seven copies in
///   agreement is a standing tax; one resolution point is not.
///
/// ## Why this, and not a protocol over `HealthKitManager`
///
/// The obvious "provider architecture" move is a `HealthDataProviding`
/// protocol with a live implementation and a mock one. That was considered and
/// rejected: `HealthKitManager`'s surface is fifteen-odd methods returning
/// HealthKit's own types (`HKCategorySample`, `HKWorkout`, `HKQueryAnchor`), so
/// such a protocol would either leak those types straight through — abstracting
/// nothing — or require a parallel DTO layer for all of them, which is a large,
/// risky change bought for no capability the app doesn't already have. The app
/// *already* has a working sample-data path (`loadMockData`); what it lacked was
/// a single place that decides when to take it. That gap is this type.
enum DataEnvironment: Equatable {

    /// Read the wearer's real Health data.
    case live

    /// Serve the bundled sample dataset, for the stated reason.
    case sample(Reason)

    enum Reason: Equatable {
        /// Launched with `-zoonDemo YES` — screenshot capture and demos.
        case demoLaunchArgument
        /// No Health store on this device at all.
        case healthDataUnavailable
    }

    /// Resolves the environment from the current process.
    ///
    /// The demo check comes first deliberately; see the type's note on ordering.
    static var current: DataEnvironment {
        if LaunchOptions.isDemo { return .sample(.demoLaunchArgument) }
        if !HealthKitManager.isHealthDataAvailable { return .sample(.healthDataUnavailable) }
        return .live
    }

    var isSample: Bool {
        if case .sample = self { return true }
        return false
    }

    var isLive: Bool { self == .live }

    /// What to write to the log when falling back, or `nil` when live.
    /// Keeps the two existing log lines' wording attached to the reason that
    /// produced them rather than to the call site that happened to notice.
    var fallbackLogMessage: String? {
        switch self {
        case .live: nil
        case .sample(.demoLaunchArgument): "Demo launch argument — using mock data"
        case .sample(.healthDataUnavailable): "HealthKit unavailable — using mock data"
        }
    }
}

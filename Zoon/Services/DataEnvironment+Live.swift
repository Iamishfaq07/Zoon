import Foundation

/// The one place `DataEnvironment` is actually resolved from the running
/// process. Split from the enum itself (`Shared/DataEnvironment.swift`)
/// because this half depends on `HealthKitManager` and `LaunchOptions`,
/// both app-only — see that file's doc comment for why the split, not just
/// the dependency, is what matters.
extension DataEnvironment {

    /// Resolves the environment from the current process.
    ///
    /// The demo check comes first deliberately; see the type's note on ordering.
    ///
    /// `@MainActor` because `HealthKitManager` is, and reading its
    /// `isHealthDataAvailable` from a nonisolated context is a compile error
    /// under strict concurrency. Every caller is already on the main actor
    /// (`SleepDataCoordinator` is `@MainActor` in its entirety), so this
    /// costs nothing at the call sites.
    @MainActor
    static var current: DataEnvironment {
        if LaunchOptions.isDemo { return .sample(.demoLaunchArgument) }
        if !HealthKitManager.isHealthDataAvailable { return .sample(.healthDataUnavailable) }
        return .live
    }
}

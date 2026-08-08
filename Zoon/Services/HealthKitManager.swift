import Foundation
import HealthKit
import os

/// Owns the `HKHealthStore` and every query the app makes.
///
/// Design notes worth knowing before you change anything here:
///
/// - **You cannot detect read-permission denial.** `requestAuthorization` succeeds
///   whether the user grants or denies read access, and
///   `authorizationStatus(for:)` only ever reports *write* permission. This is
///   deliberate on Apple's part — it stops apps from inferring that you have
///   health data you're choosing to hide. The practical consequence is that
///   "authorized" is not a state this app can know. We model reality instead:
///   we either have data or we don't (`SleepDataState`).
///
/// - **Nothing works in the Simulator.** There is no sleep data to read. The
///   coordinator falls back to `MockData` there; see `ZoonApp.swift`.
@MainActor
@Observable
final class HealthKitManager {

    private let store = HKHealthStore()
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "HealthKit")

    // Deliberately no `isAuthorized` / `lastError` state here. Read permission
    // is unknowable (see above), and error presentation belongs to
    // `SleepDataCoordinator.State`, which is what the views actually observe —
    // a second source of truth would only drift from it.

    /// Live observer queries, retained so we can stop them. Without this the
    /// observers leak and re-registering stacks duplicates that each fire a
    /// redundant refresh.
    private var activeObservers: [HKObserverQuery] = []

    static var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Types

    /// Everything the app reads. Zoon requests **read access only** — the
    /// `toShare` set is empty, so it can never write to Health.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.activeEnergyBurned),
            // The signal behind Apple Watch's sleep apnea notifications
            // (iOS 18+). Only Series 9 / Ultra 2 and later record it, and only
            // when the user has enabled the feature — everywhere else the query
            // simply returns nothing, which the extractor handles as nil.
            HKQuantityType(.appleSleepingBreathingDisturbances),
            HKObjectType.workoutType()
        ]
        // Wrist temperature needs a Series 8 / Ultra or later. The type exists
        // from iOS 16; on hardware that can't measure it the queries simply
        // return nothing, which the extractor handles as `nil`.
        types.insert(HKQuantityType(.appleSleepingWristTemperature))
        return types
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard Self.isHealthDataAvailable else {
            throw HealthKitError.unavailable
        }
        // Empty `toShare`: read-only by construction, not by convention.
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Background delivery

    /// Registers an observer so new sleep data is picked up without polling.
    ///
    /// Must be called on every launch, not just after the permission sheet:
    /// observer queries do not survive process death, and background delivery
    /// relaunches the app expecting a registered observer to be waiting.
    ///
    /// Requires the **HealthKit background delivery** capability. Without it
    /// `enableBackgroundDelivery` fails — we log that rather than swallowing it,
    /// because a silent failure here looks exactly like "the app just doesn't
    /// update", which is miserable to debug.
    ///
    /// Note that HealthKit clamps `.immediate` to roughly hourly for
    /// non-critical types like sleep. Expect "some time after you wake up", not
    /// "the instant the watch syncs".
    func startObservingSleep(onChange: @escaping @Sendable () async -> Void) {
        guard Self.isHealthDataAvailable else { return }
        stopObserving()

        let sleepType = HKCategoryType(.sleepAnalysis)
        // Note on captures: the query handler holds `self` weakly, so inside it
        // `self` is already Optional. The nested Task captures that Optional
        // directly — writing `[weak self]` a second time would be applying
        // `weak` to an already-optional binding.
        let observer = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error {
                // Logged, not surfaced: an observer hiccup shouldn't put a red
                // banner in front of the user.
                Task { @MainActor in
                    self?.logger.error("Observer query error: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                Task { await onChange() }
            }
            // MUST be called, even on error. HealthKit will stop delivering
            // updates to an observer that doesn't acknowledge them.
            completionHandler()
        }

        store.execute(observer)
        activeObservers.append(observer)

        store.enableBackgroundDelivery(for: sleepType, frequency: .hourly) { [weak self] success, error in
            Task { @MainActor in
                if let error {
                    self?.logger.notice(
                        """
                        Background delivery unavailable: \(error.localizedDescription, privacy: .public). \
                        The app still refreshes on foreground; add the HealthKit background delivery \
                        capability to enable automatic morning updates.
                        """
                    )
                } else if success {
                    self?.logger.info("Background delivery enabled for sleepAnalysis")
                }
            }
        }
    }

    func stopObserving() {
        for observer in activeObservers { store.stop(observer) }
        activeObservers.removeAll()
    }

    // MARK: - Sleep samples

    /// Anchored fetch of sleep samples.
    ///
    /// `HKAnchoredObjectQuery` is the right tool for incremental sync: it returns
    /// only what changed since the last anchor, including deletions, so a morning
    /// refresh doesn't re-download months of samples.
    ///
    /// - Parameter anchor: the anchor persisted from the previous run, or `nil`
    ///   for a full initial sync of the window.
    /// - Returns: new/updated samples, deleted object UUIDs, and the new anchor
    ///   to persist.
    func fetchSleepSamples(
        since anchor: HKQueryAnchor?,
        window: DateInterval
    ) async throws -> SleepFetchResult {
        let sleepType = HKCategoryType(.sleepAnalysis)
        // No `.strictStartDate`: a night that began before the window opens still
        // belongs to us. Strict start would drop the first hours of an ongoing
        // or straddling session.
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sleepType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: SleepFetchResult(
                    samples: (samples as? [HKCategorySample]) ?? [],
                    deletedUUIDs: (deleted ?? []).map(\.uuid),
                    anchor: newAnchor
                ))
            }
            store.execute(query)
        }
    }

    /// Non-incremental fetch, used for backfilling history on first launch and
    /// whenever we need a complete picture rather than a delta.
    func fetchAllSleepSamples(in window: DateInterval) async throws -> [HKCategorySample] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Quantity statistics

    /// Average of a quantity type over an interval.
    ///
    /// The predicate deliberately omits `.strictStartDate`/`.strictEndDate`: an
    /// HRV reading that began a minute before sleep onset is still an overnight
    /// reading, and strict options would throw it away.
    func average(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in interval: DateInterval
    ) async throws -> Double? {
        try await statistic(identifier, unit: unit, in: interval, options: .discreteAverage) {
            $0.averageQuantity()
        }
    }

    func minimum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in interval: DateInterval
    ) async throws -> Double? {
        try await statistic(identifier, unit: unit, in: interval, options: .discreteMin) {
            $0.minimumQuantity()
        }
    }

    func sum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in interval: DateInterval
    ) async throws -> Double? {
        try await statistic(identifier, unit: unit, in: interval, options: .cumulativeSum) {
            $0.sumQuantity()
        }
    }

    private func statistic(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in interval: DateInterval,
        options: HKStatisticsOptions,
        extract: @escaping @Sendable (HKStatistics) -> HKQuantity?
    ) async throws -> Double? {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, error in
                if let error {
                    // "No data" arrives as an error for some types. That is a
                    // normal result, not a failure — a night with no SpO2
                    // readings is just a night with no SpO2 readings.
                    if (error as? HKError)?.code == .errorNoData {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let statistics else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: extract(statistics)?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    // MARK: - Intraday series

    /// Mean heart rate per hour across an interval.
    ///
    /// `HKStatisticsCollectionQuery` is the right tool here: asking for raw
    /// samples across a day returns thousands of them and we'd bucket them
    /// ourselves anyway. HealthKit does the bucketing in its own store, which is
    /// dramatically faster and uses a fraction of the memory.
    ///
    /// Hours with no coverage are **omitted**, never zero-filled. A watch on the
    /// charger is not a resting hour, and Body Battery would happily "charge"
    /// through it if we pretended otherwise.
    func hourlyHeartRate(in interval: DateInterval) async throws -> [(date: Date, bpm: Double)] {
        try await hourlySeries(
            .heartRate,
            unit: .beatsPerMinute,
            options: .discreteAverage,
            interval: interval
        ) { $0.averageQuantity() }
    }

    /// Active energy burned per hour, for the strain estimate fallback.
    func hourlyActiveEnergy(in interval: DateInterval) async throws -> [(date: Date, bpm: Double)] {
        try await hourlySeries(
            .activeEnergyBurned,
            unit: .kilocalorie(),
            options: .cumulativeSum,
            interval: interval
        ) { $0.sumQuantity() }
    }

    private func hourlySeries(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        interval: DateInterval,
        extract: @escaping @Sendable (HKStatistics) -> HKQuantity?
    ) async throws -> [(date: Date, bpm: Double)] {

        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)

        // Anchor on the hour so buckets line up with wall-clock hours rather
        // than with whatever minute the query happened to run.
        let anchorDate = Calendar.current.dateInterval(of: .hour, for: interval.start)?.start ?? interval.start

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchorDate,
                intervalComponents: DateComponents(hour: 1)
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    if (error as? HKError)?.code == .errorNoData {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }

                var results: [(date: Date, bpm: Double)] = []
                collection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                    if let quantity = extract(statistics) {
                        results.append((date: statistics.startDate, bpm: quantity.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: results)
            }

            store.execute(query)
        }
    }

    /// Minutes spent in each heart-rate zone across an interval.
    ///
    /// Zones are defined on **heart-rate reserve** (Karvonen) rather than raw
    /// percentage of max, because HRR accounts for the user's own resting rate.
    /// Two people with the same max but a 20bpm difference in resting HR are not
    /// working equally hard at 140bpm, and a %max model says they are.
    ///
    /// Built from hourly means, so it's an approximation: an hour containing a
    /// 20-minute interval session averages out to something moderate. It's
    /// directionally right and it's what's cheaply available; the UI flags
    /// strain as an estimate whenever coverage is thin.
    func heartRateZones(
        in interval: DateInterval,
        restingHeartRate: Double,
        maxHeartRate: Double
    ) async throws -> (zones: [StrainScore.Zone: Double], coverage: Double) {

        let hourly = try await hourlyHeartRate(in: interval)
        guard !hourly.isEmpty else { return ([:], 0) }

        let reserve = max(20, maxHeartRate - restingHeartRate)
        var zones: [StrainScore.Zone: Double] = [:]

        for sample in hourly {
            let hrr = (sample.bpm - restingHeartRate) / reserve
            // Highest zone whose lower bound is cleared.
            guard let zone = StrainScore.Zone.allCases
                .filter({ hrr >= $0.lowerBoundHRR })
                .max(by: { $0.lowerBoundHRR < $1.lowerBoundHRR }) else { continue }
            zones[zone, default: 0] += 60
        }

        let expectedHours = max(1, interval.duration / 3600)
        return (zones, min(1, Double(hourly.count) / expectedHours))
    }

    // MARK: - Workouts

    /// The most recent workout ending before `date`, within the preceding 24h.
    func lastWorkout(before date: Date) async throws -> HKWorkout? {
        let start = date.addingTimeInterval(-24 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: date)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKWorkout)
                }
            }
            store.execute(query)
        }
    }
}

// MARK: - Supporting types

struct SleepFetchResult {
    let samples: [HKCategorySample]
    let deletedUUIDs: [UUID]
    let anchor: HKQueryAnchor?
}

enum HealthKitError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Health data isn't available on this device. Zoon needs an iPhone with the Health app."
        }
    }
}

// MARK: - Anchor persistence

/// Persists the `HKQueryAnchor` between launches so incremental sync survives
/// process death. `UserDefaults` is fine here — it's an opaque cursor, not
/// health data.
enum AnchorStore {

    private static let key = "zoon.sleep.anchor"

    static func load() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    static func save(_ anchor: HKQueryAnchor?) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

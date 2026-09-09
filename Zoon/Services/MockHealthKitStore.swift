import Foundation
import HealthKit

/// Synthetic HealthKit samples for the Simulator and for unit tests.
///
/// The real `HKHealthStore` has nothing to say on a Simulator and is not
/// constructible in a way that lets tests inject samples with a custom
/// `sourceRevision`. This type generates the *streams* the rest of the
/// pipeline already knows how to read -- sleep analysis, HR, HRV, SpO2,
/// wrist temperature, respiratory rate, breathing disturbances, and (when
/// the SDK knows the type) sleep-apnea events -- so CI and the Simulator
/// exercise the same join logic a real night does.
///
/// It is a factory, not a store: nothing is persisted, and nothing here
/// replaces `MockData`, which is the feature-struct shortcut the UI uses
/// when HealthKit is unavailable. Tests that need `HKCategorySample`
/// values (session building, fusion) come here.
enum MockHealthKitStore: Sendable {

    struct NightSpec: Sendable {
        var wakeDate: Date
        var bedtimeHour: Int
        var durationHours: Double
        var includeStages: Bool
        var includeApneaEvents: Int

        static func typical(wakeDate: Date) -> NightSpec {
            NightSpec(
                wakeDate: wakeDate,
                bedtimeHour: 23,
                durationHours: 7.5,
                includeStages: true,
                includeApneaEvents: 0
            )
        }
    }

    /// A staged night whose segments tile bedtime → wake with no overlap.
    /// Used to prove the builder's clustering and the extractor's join
    /// against a known ground truth, without a live health store.
    static func sleepAnalysisSamples(for spec: NightSpec, calendar: Calendar = .current) -> [HKCategorySample] {
        let wakeDay = calendar.startOfDay(for: spec.wakeDate)
        guard let bedtime = calendar.date(byAdding: .hour, value: spec.bedtimeHour - 24, to: wakeDay) else {
            return []
        }
        let wake = bedtime.addingTimeInterval(spec.durationHours * 3600)
        let type = HKCategoryType(.sleepAnalysis)

        func sample(_ value: HKCategoryValueSleepAnalysis, from: Date, hours: Double) -> HKCategorySample {
            HKCategorySample(
                type: type,
                value: value.rawValue,
                start: from,
                end: from.addingTimeInterval(hours * 3600)
            )
        }

        if !spec.includeStages {
            return [sample(.asleepUnspecified, from: bedtime, hours: spec.durationHours)]
        }

        // A plausible adult mix: a little latency, then cycles of
        // core → deep → core → REM, ending near wake.
        var cursor = bedtime
        var samples: [HKCategorySample] = [
            sample(.inBed, from: bedtime, hours: spec.durationHours)
        ]
        samples.append(sample(.awake, from: cursor, hours: 0.2))
        cursor = cursor.addingTimeInterval(0.2 * 3600)

        let remaining = spec.durationHours - 0.2
        let cycles = max(1, Int(remaining / 1.5))
        let slice = remaining / Double(cycles)
        for _ in 0..<cycles {
            let core = slice * 0.45
            let deep = slice * 0.25
            let rem = slice * 0.25
            let wakeGap = slice * 0.05
            samples.append(sample(.asleepCore, from: cursor, hours: core))
            cursor = cursor.addingTimeInterval(core * 3600)
            samples.append(sample(.asleepDeep, from: cursor, hours: deep))
            cursor = cursor.addingTimeInterval(deep * 3600)
            samples.append(sample(.asleepCore, from: cursor, hours: rem * 0.4))
            cursor = cursor.addingTimeInterval(rem * 0.4 * 3600)
            samples.append(sample(.asleepREM, from: cursor, hours: rem * 0.6))
            cursor = cursor.addingTimeInterval(rem * 0.6 * 3600)
            if wakeGap > 0, cursor < wake {
                samples.append(sample(.awake, from: cursor, hours: wakeGap))
                cursor = cursor.addingTimeInterval(wakeGap * 3600)
            }
        }
        return samples.filter { $0.endDate <= wake.addingTimeInterval(1) }
    }

    static func heartRateSamples(in interval: DateInterval, resting: Double = 54) -> [HKQuantitySample] {
        quantitySamples(
            .heartRate,
            unit: .count().unitDivided(by: .minute()),
            in: interval,
            every: 5 * 60,
            value: { minute in
                // Slight overnight dip, then a pre-wake rise.
                let t = minute / max(1, interval.duration / 60)
                return resting - 6 * sin(t * .pi) + Double.random(in: -1...1)
            }
        )
    }

    static func hrvSamples(in interval: DateInterval, baseline: Double = 48) -> [HKQuantitySample] {
        quantitySamples(
            .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            in: interval,
            every: 15 * 60,
            value: { _ in baseline + Double.random(in: -6...6) }
        )
    }

    static func oxygenSamples(in interval: DateInterval) -> [HKQuantitySample] {
        quantitySamples(
            .oxygenSaturation,
            unit: .percent(),
            in: interval,
            every: 10 * 60,
            value: { _ in 0.96 + Double.random(in: -0.01...0.01) }
        )
    }

    static func wristTemperatureSamples(in interval: DateInterval, celsius: Double = 36.4) -> [HKQuantitySample] {
        quantitySamples(
            .appleSleepingWristTemperature,
            unit: .degreeCelsius(),
            in: interval,
            every: 60 * 60,
            value: { _ in celsius + Double.random(in: -0.1...0.1) }
        )
    }

    static func respiratorySamples(in interval: DateInterval) -> [HKQuantitySample] {
        quantitySamples(
            .respiratoryRate,
            unit: .count().unitDivided(by: .minute()),
            in: interval,
            every: 10 * 60,
            value: { _ in 14 + Double.random(in: -1.5...1.5) }
        )
    }

    static func breathingDisturbanceSamples(in interval: DateInterval, fraction: Double = 0.04) -> [HKQuantitySample] {
        quantitySamples(
            .appleSleepingBreathingDisturbances,
            unit: .percent(),
            in: interval,
            every: interval.duration,
            value: { _ in fraction }
        )
    }

    /// Discrete apnea-event category samples, if this SDK knows the type.
    static func apneaEventSamples(in interval: DateInterval, count: Int) -> [HKCategorySample] {
        guard count > 0, let type = apneaEventType else { return [] }
        let span = interval.duration
        return (0..<count).map { index in
            let offset = span * Double(index + 1) / Double(count + 1)
            let start = interval.start.addingTimeInterval(offset)
            return HKCategorySample(type: type, value: 0, start: start, end: start.addingTimeInterval(8))
        }
    }

    /// One typical night, every stream the extractor reads.
    static func nightStreams(wakeDate: Date, calendar: Calendar = .current) -> (
        sleep: [HKCategorySample],
        heartRate: [HKQuantitySample],
        hrv: [HKQuantitySample],
        oxygen: [HKQuantitySample],
        wristTemp: [HKQuantitySample],
        respiratory: [HKQuantitySample],
        breathing: [HKQuantitySample],
        apnea: [HKCategorySample]
    ) {
        let spec = NightSpec.typical(wakeDate: wakeDate)
        let sleep = sleepAnalysisSamples(for: spec, calendar: calendar)
        guard let start = sleep.map(\.startDate).min(),
              let end = sleep.map(\.endDate).max() else {
            return ([], [], [], [], [], [], [], [])
        }
        let interval = DateInterval(start: start, end: end)
        return (
            sleep: sleep,
            heartRate: heartRateSamples(in: interval),
            hrv: hrvSamples(in: interval),
            oxygen: oxygenSamples(in: interval),
            wristTemp: wristTemperatureSamples(in: interval),
            respiratory: respiratorySamples(in: interval),
            breathing: breathingDisturbanceSamples(in: interval),
            apnea: apneaEventSamples(in: interval, count: spec.includeApneaEvents)
        )
    }

    private static func quantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in interval: DateInterval,
        every: TimeInterval,
        value: (Double) -> Double
    ) -> [HKQuantitySample] {
        let type = HKQuantityType(identifier)
        var samples: [HKQuantitySample] = []
        var cursor = interval.start
        var minute = 0.0
        while cursor < interval.end {
            let quantity = HKQuantity(unit: unit, doubleValue: value(minute))
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: cursor, end: cursor.addingTimeInterval(1)))
            cursor = cursor.addingTimeInterval(every)
            minute += every / 60
        }
        return samples
    }

    private static var apneaEventType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: "HKCategoryTypeIdentifierSleepApneaEvent"))
    }
}

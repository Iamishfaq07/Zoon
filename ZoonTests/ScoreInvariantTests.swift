import XCTest

/// Properties every score must hold across the whole input space, not just at
/// the handful of points the unit tests name.
///
/// The engines are each covered by their own tests, which check that a
/// particular night produces a particular number. Those tests cannot catch a
/// score that goes to 104 on an input nobody thought to write down, or one
/// that falls when a night gets better. These sweep a seeded range of inputs
/// and assert the things that must be true everywhere.
///
/// Seeded rather than random: a failure has to be reproducible, and a suite
/// that passes or fails depending on the day is worse than no suite. The
/// generator below is a plain LCG so the sequence is identical on every
/// machine and every run.
final class ScoreInvariantTests: XCTestCase {

    /// Deterministic pseudo-random source. Not for cryptography; for covering
    /// an input space the same way twice.
    private struct Seeded {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }

        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }

        mutating func double(_ range: ClosedRange<Double>) -> Double {
            range.lowerBound + next() * (range.upperBound - range.lowerBound)
        }

        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() * Double(range.count - 1).rounded())
        }

        /// `nil` at the given rate, so the sweep covers missing signals as
        /// well as present ones -- missing is where these engines have
        /// historically gone wrong.
        mutating func maybe(_ range: ClosedRange<Double>, missingRate: Double = 0.25) -> Double? {
            next() < missingRate ? nil : double(range)
        }
    }

    private let iterations = 400

    // MARK: - Recovery

    func testRecoveryStaysInRangeAcrossTheInputSpace() {
        var rng = Seeded(seed: 0x5EC0_FFEE_0001)
        for i in 0..<iterations {
            let night = Fixture.night(
                timeAsleepMinutes: rng.double(0...780),
                avgHRV: rng.maybe(10...180),
                restingHeartRate: rng.maybe(35...95),
                avgRespiratoryRate: rng.maybe(8...28),
                wristTempDeltaC: rng.maybe(-2...2)
            )
            let baseline = RecoveryBaseline(
                hrv: rng.maybe(10...180),
                restingHeartRate: rng.maybe(35...95),
                respiratoryRate: rng.maybe(8...28),
                wristTemperature: rng.maybe(-2...2),
                nightCount: rng.int(0...60)
            )
            let score = RecoveryScore.compute(
                features: night,
                baseline: baseline,
                sleepPerformance: rng.double(0...140)
            )

            XCTAssertTrue((0...100).contains(score.percent), "iteration \(i) produced \(score.percent)")
            XCTAssertTrue(
                (0...100).contains(score.dataCompletenessPercent),
                "iteration \(i) reported \(score.dataCompletenessPercent)% coverage"
            )
            XCTAssertTrue(
                (0...4).contains(score.availableComponentCount),
                "iteration \(i) counted \(score.availableComponentCount) of four components"
            )
            XCTAssertEqual(
                score.availableComponentCount,
                score.components.filter(\.isAvailable).count,
                "the count must match the components it counts"
            )
        }
    }

    func testRecoveryIsDeterministic() {
        let night = Fixture.night(avgHRV: 61, restingHeartRate: 52)
        let baseline = RecoveryBaseline(
            hrv: 55, restingHeartRate: 54, respiratoryRate: 14.5,
            wristTemperature: 0, nightCount: 30
        )
        let first = RecoveryScore.compute(features: night, baseline: baseline, sleepPerformance: 92)
        let second = RecoveryScore.compute(features: night, baseline: baseline, sleepPerformance: 92)
        XCTAssertEqual(first, second, "the same night must score the same twice")
    }

    /// Higher HRV against the same baseline is a better night by this model's
    /// own definition. If it ever isn't, the weighting has a sign error.
    func testRecoveryRisesWithHRV() {
        let baseline = RecoveryBaseline(
            hrv: 55, restingHeartRate: 54, respiratoryRate: 14.5,
            wristTemperature: 0, nightCount: 30
        )
        var previous = -1
        for hrv in stride(from: 30.0, through: 90.0, by: 5.0) {
            let score = RecoveryScore.compute(
                features: Fixture.night(avgHRV: hrv),
                baseline: baseline,
                sleepPerformance: 90
            ).percent
            XCTAssertGreaterThanOrEqual(score, previous, "recovery fell as HRV rose, at \(hrv)ms")
            previous = score
        }
    }

    /// Removing a signal must never make the score look better-founded.
    func testDroppingASignalNeverRaisesCoverage() {
        let baseline = RecoveryBaseline(
            hrv: 55, restingHeartRate: 54, respiratoryRate: 14.5,
            wristTemperature: 0, nightCount: 30
        )
        let full = RecoveryScore.compute(
            features: Fixture.night(), baseline: baseline, sleepPerformance: 90
        )
        let withoutHRV = RecoveryScore.compute(
            features: Fixture.night(avgHRV: nil), baseline: baseline, sleepPerformance: 90
        )

        XCTAssertLessThan(withoutHRV.dataCompletenessPercent, full.dataCompletenessPercent)
        XCTAssertLessThan(withoutHRV.availableComponentCount, full.availableComponentCount)
        XCTAssertLessThanOrEqual(
            withoutHRV.confidence, full.confidence,
            "losing a signal cannot raise confidence"
        )
    }

    // MARK: - Load

    func testLoadStaysWithinItsScale() {
        var rng = Seeded(seed: 0x10AD_0002)
        for i in 0..<iterations {
            var zones: [StrainScore.Zone: Double] = [:]
            for zone in StrainScore.Zone.allCases {
                if rng.next() < 0.7 { zones[zone] = rng.double(0...400) }
            }
            let score = StrainScore.compute(
                zoneMinutes: zones,
                activeEnergyKcal: rng.maybe(0...6000),
                hasHeartRateCoverage: rng.next() < 0.8
            )
            XCTAssertTrue(
                (0...StrainScore.maxValue).contains(score.value),
                "iteration \(i) produced \(score.value), outside 0...\(StrainScore.maxValue)"
            )
            XCTAssertFalse(score.value.isNaN, "iteration \(i) produced NaN")
        }
    }

    /// Absurd input is the case a saturating scale exists for.
    func testLoadSaturatesRatherThanOverflowing() {
        let absurd = StrainScore.compute(
            zoneMinutes: [.maximum: 100_000],
            activeEnergyKcal: 99_999,
            hasHeartRateCoverage: true
        )
        XCTAssertLessThanOrEqual(absurd.value, StrainScore.maxValue)
        XCTAssertGreaterThan(absurd.value, 18, "a day like that is not Moderate")
    }

    func testMoreMinutesNeverLowersLoad() {
        var previous = -1.0
        for minutes in stride(from: 0.0, through: 240.0, by: 10.0) {
            let value = StrainScore.compute(
                zoneMinutes: [.vigorous: minutes],
                activeEnergyKcal: nil,
                hasHeartRateCoverage: true
            ).value
            XCTAssertGreaterThanOrEqual(value, previous, "load fell as minutes rose, at \(minutes)")
            previous = value
        }
    }

    /// The same wall-clock time spent harder must cost more. This is the
    /// premise of a zone-weighted model; if it fails, the weights are wrong.
    func testHarderZonesCostMoreForTheSameTime() {
        let ordered = StrainScore.Zone.allCases.sorted { $0.lowerBoundHRR < $1.lowerBoundHRR }
        var previous = -1.0
        for zone in ordered {
            let value = StrainScore.compute(
                zoneMinutes: [zone: 45],
                activeEnergyKcal: nil,
                hasHeartRateCoverage: true
            ).value
            XCTAssertGreaterThan(value, previous, "\(zone.label) scored no higher than the zone below it")
            previous = value
        }
    }

    func testNoActivityScoresZeroRatherThanAFloor() {
        let idle = StrainScore.compute(
            zoneMinutes: [:], activeEnergyKcal: 0, hasHeartRateCoverage: true
        )
        XCTAssertEqual(idle.value, 0, accuracy: 0.0001, "a day with nothing in it is not a light workout")
    }

    // MARK: - Energy

    func testOvernightChargeStaysInRange() {
        var rng = Seeded(seed: 0xE4E4_0003)
        for i in 0..<iterations {
            let charge = BodyBattery.overnightCharge(
                recoveryPercent: rng.next() < 0.3 ? nil : rng.int(0...100),
                sleepPerformance: rng.double(0...160)
            )
            XCTAssertTrue(
                (0...100).contains(charge),
                "iteration \(i) woke up at \(charge)%"
            )
        }
    }

    /// A better night cannot leave someone with less in the tank.
    func testOvernightChargeRisesWithSleep() {
        var previous = -1.0
        for performance in stride(from: 0.0, through: 100.0, by: 5.0) {
            let charge = BodyBattery.overnightCharge(recoveryPercent: 70, sleepPerformance: performance)
            XCTAssertGreaterThanOrEqual(charge, previous, "charge fell as sleep improved, at \(performance)%")
            previous = charge
        }
    }
}

import XCTest

final class EnergyForecastTests: XCTestCase {

    private let wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!

    // MARK: - compute

    func testComputeProducesFiveWindowsInChronologicalOrder() {
        let forecast = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil)
        XCTAssertEqual(forecast.windows.count, 5)
        let times = forecast.windows.map(\.time)
        XCTAssertEqual(times, times.sorted())
    }

    func testComputeMarksGenericWindDownWhenNoPersonalHourGiven() {
        let forecast = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil)
        XCTAssertTrue(forecast.isGenericWindDown)
        let windDown = forecast.windows.first { $0.kind == .windDown }
        XCTAssertEqual(windDown?.time, wake.addingTimeInterval(15.5 * 3600))
    }

    func testComputeUsesPersonalWindDownHourWhenProvided() {
        let forecast = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: -0.5)
        XCTAssertFalse(forecast.isGenericWindDown)
    }

    func testComputePullsAfternoonDipEarlierWithHigherSleepDebt() {
        let rested = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil)
        let debted = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 300, windDownHour: nil)
        let restedDip = rested.windows.first { $0.kind == .afternoonDip }!.time
        let debtedDip = debted.windows.first { $0.kind == .afternoonDip }!.time
        XCTAssertLessThan(debtedDip, restedDip)
    }

    func testComputeDelaysMorningPeakWithHigherSleepDebt() {
        let rested = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil)
        let debted = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 300, windDownHour: nil)
        let restedPeak = rested.windows.first { $0.kind == .morningPeak }!.time
        let debtedPeak = debted.windows.first { $0.kind == .morningPeak }!.time
        XCTAssertGreaterThan(debtedPeak, restedPeak)
    }

    func testComputeIgnoresNegativeSleepDebt() {
        // Negative debt (surplus sleep) is clamped to 0 via max(0, ...), so
        // it must produce the identical curve to zero debt, not an
        // "extra-rested" curve that shifts the other direction.
        let zero = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil)
        let negative = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: -200, windDownHour: nil)
        XCTAssertEqual(zero.windows.map(\.time), negative.windows.map(\.time))
    }

    // MARK: - resolve (via windDownHour)

    func testResolveNegativeHourLandsOnTheEveningOfWakeDay() {
        // -0.5 -> 23:30 the same calendar day as wake, not the day after.
        let forecast = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: -0.5)
        let windDown = forecast.windows.first { $0.kind == .windDown }!.time
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: windDown), calendar.component(.day, from: wake))
        XCTAssertEqual(calendar.component(.hour, from: windDown), 23)
        XCTAssertEqual(calendar.component(.minute, from: windDown), 30)
    }

    func testResolvePositiveHourLandsAfterMidnight() {
        // 0.5 -> 00:30, the next calendar day after wake.
        let forecast = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: 0.5)
        let windDown = forecast.windows.first { $0.kind == .windDown }!.time
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.hour, from: windDown), 0)
        XCTAssertEqual(calendar.component(.minute, from: windDown), 30)
    }

    // MARK: - curveSamples

    func testCurveSamplesReturnsEmptyForFewerThanTwoSamples() {
        let forecast = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil)
        XCTAssertTrue(forecast.curveSamples(count: 1).isEmpty)
    }

    func testCurveSamplesSpansFromFirstToLastWindow() {
        let forecast = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil)
        let samples = forecast.curveSamples(count: 20)
        XCTAssertEqual(samples.first?.time, forecast.windows.first?.time)
        XCTAssertEqual(samples.last?.time, forecast.windows.last?.time)
    }

    func testCurveSamplesLevelsStayWithinZeroToOne() {
        let forecast = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil)
        let samples = forecast.curveSamples(count: 50)
        XCTAssertTrue(samples.allSatisfy { $0.level >= 0 && $0.level <= 1 })
    }

    func testCurveSamplesPeaksNearTheMorningPeakWindow() {
        // morningPeak has the highest level (1.0) of any anchor; a sample
        // taken right at that time should be close to 1.0, not somewhere
        // between two lower anchors.
        let forecast = EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil)
        let peakTime = forecast.windows.first { $0.kind == .morningPeak }!.time
        let samples = forecast.curveSamples(count: 200)
        let closest = samples.min { abs($0.time.timeIntervalSince(peakTime)) < abs($1.time.timeIntervalSince(peakTime)) }
        XCTAssertGreaterThan(closest!.level, 0.95)
    }
}

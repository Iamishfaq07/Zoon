import XCTest

/// Energy has always known its hourly deltas and never said what was
/// happening in those hours. These pin the attribution — and, just as much,
/// what it refuses to attribute.
final class EnergyDriversTests: XCTestCase {

    private let wake = Date(timeIntervalSince1970: 1_772_000_000)

    private func battery(deltas: [Double], start: Double = 100) -> BodyBattery {
        var level = start
        var points: [BodyBattery.Point] = [
            BodyBattery.Point(date: wake, level: level, delta: 0)
        ]
        for (hour, delta) in deltas.enumerated() {
            level += delta
            points.append(
                BodyBattery.Point(
                    date: wake.addingTimeInterval(Double(hour + 1) * 3600),
                    level: level,
                    delta: delta
                )
            )
        }
        return BodyBattery(
            points: points,
            current: Int(level.rounded()),
            morningPeak: Int(start.rounded()),
            dayLow: Int(level.rounded())
        )
    }

    private func workout(_ label: String, atHour hour: Int, minutes: Double = 45) -> EnergyDrivers.NamedInterval {
        // Point `hour` sits at wake + (hour + 1) hours, matching how
        // `battery(deltas:)` lays the curve out: an anchor at waking, then one
        // point per elapsed hour.
        let start = wake.addingTimeInterval(Double(hour + 1) * 3600 + 600)
        return EnergyDrivers.NamedInterval(
            label: label, symbol: "figure.run",
            start: start, end: start.addingTimeInterval(minutes * 60)
        )
    }

    // MARK: - Refusals

    /// A curve whose provenance forbids showing a number must not have that
    /// number smuggled out as an attributed drain.
    func testAnUnpresentableCurveExplainsNothing() {
        let state = EnergyDrivers.explain(
            battery: battery(deltas: [-10, -12, -8]), workouts: [], isPresentable: false
        )
        XCTAssertEqual(state, .notEnoughYet)
        XCTAssertTrue(state.drivers.isEmpty)
    }

    func testTooEarlyInTheDayExplainsNothing() {
        let bare = BodyBattery(
            points: [BodyBattery.Point(date: wake, level: 90, delta: 0)],
            current: 90, morningPeak: 90, dayLow: 90
        )
        XCTAssertEqual(
            EnergyDrivers.explain(battery: bare, workouts: [], isPresentable: true),
            .notEnoughYet
        )
    }

    /// A few points of drift over a morning is the curve breathing, not a
    /// story. It reports the change and declines to explain it.
    func testASmallChangeIsReportedButNotExplained() {
        let state = EnergyDrivers.explain(
            battery: battery(deltas: [-1, -1, -1]), workouts: [], isPresentable: true
        )
        XCTAssertEqual(state, .steady(spent: 3))
        XCTAssertTrue(state.drivers.isEmpty)
        XCTAssertEqual(state.headline, "Down 3 since waking")
    }

    /// An evenly-draining day has no driver to name, and saying so is a real
    /// answer rather than a failure.
    func testAnEvenlyDrainingDayNamesNoDriver() {
        let state = EnergyDrivers.explain(
            battery: battery(deltas: [-2, -2, -2, -2, -2, -2]), workouts: [], isPresentable: true
        )
        XCTAssertEqual(state, .steady(spent: 12), "ordinary waking metabolism is not a driver")
    }

    // MARK: - Attribution

    func testAWorkoutHourIsAttributedToTheWorkout() throws {
        let state = EnergyDrivers.explain(
            battery: battery(deltas: [-2, -18, -2]),
            workouts: [workout("Afternoon run", atHour: 1)],
            isPresentable: true
        )
        guard case .explained(let spent, let drivers) = state else {
            return XCTFail("expected an explanation, got \(state)")
        }
        XCTAssertEqual(spent, 22)
        XCTAssertEqual(drivers.first?.label, "Afternoon run")
        XCTAssertEqual(drivers.first?.spent, 18)
    }

    /// Drain outside a workout that is still well above ordinary living gets
    /// named, but not attributed to something that did not happen.
    func testUnattributedNotableDrainIsCalledActiveHours() throws {
        let state = EnergyDrivers.explain(
            battery: battery(deltas: [-9, -2, -8]), workouts: [], isPresentable: true
        )
        let drivers = state.drivers
        XCTAssertEqual(drivers.count, 1)
        XCTAssertEqual(drivers.first?.label, "Active hours")
        XCTAssertEqual(drivers.first?.spent, 17, "the 2-point hour is ordinary living, not a driver")
    }

    func testDriversAreOrderedByWhatTheyCost() throws {
        let state = EnergyDrivers.explain(
            battery: battery(deltas: [-6, -20, -2]),
            workouts: [workout("Strength", atHour: 0, minutes: 40), workout("Ride", atHour: 1)],
            isPresentable: true
        )
        let labels = state.drivers.map(\.label)
        XCTAssertEqual(labels.first, "Ride", "the larger cost is named first")
        XCTAssertTrue(labels.contains("Strength"))
    }

    /// Charging hours are recovery, not spend, and must not be counted as
    /// drain by sign error.
    func testChargingHoursAreNotCountedAsSpend() {
        let state = EnergyDrivers.explain(
            battery: battery(deltas: [-12, 4, -6]), workouts: [], isPresentable: true
        )
        XCTAssertEqual(state.spent, 14, "spend is the fall from the morning peak")
        for driver in state.drivers {
            XCTAssertGreaterThan(driver.spent, 0)
        }
    }

    func testHeadlineNeverClaimsAnExplanationItDoesNotHave() {
        XCTAssertEqual(
            EnergyDrivers.explain(battery: battery(deltas: [0]), workouts: [], isPresentable: true).headline,
            "Level since waking"
        )
        XCTAssertEqual(
            EnergyDrivers.explain(
                battery: battery(deltas: [-3]), workouts: [], isPresentable: false
            ).headline,
            "Not enough of today yet"
        )
    }
}

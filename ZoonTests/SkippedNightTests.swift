import XCTest

/// A skipped night drops out of the reminder horizon and nothing else.
final class SkippedNightTests: XCTestCase {

    private var cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    func testTheKeyIsTheMorning() {
        XCTAssertEqual(PersonalSetup.nightKey(forWake: date(24, 7), calendar: cal), "2026-09-24")
    }

    /// Skipping Thursday removes Thursday's night from what reminders are
    /// scheduled for, and only Thursday's.
    func testASkippedNightLeavesTheHorizon() {
        var setup = PersonalSetup()
        setup.setSkipped(true, wake: date(24, 7), now: date(22, 12), calendar: cal)
        let plan = SleepAutopilot.Plan(
            targetBedtimeMinutes: -60, targetSleepMinutes: 480, shiftMinutes: 0,
            debtRepaymentMinutes: 0, isHolding: true, confidence: .moderate
        )
        let horizon = ResolvedSleepEpisode.horizon(
            nights: 4, autopilot: plan, usualWakeMinute: 420, needMinutes: 480,
            windDownLeadMinutes: 30, now: date(22, 12), calendar: cal
        )
        let kept = horizon.filter { !setup.isSkipped(wake: $0.wake, calendar: cal) }
        XCTAssertEqual(horizon.count, 4)
        XCTAssertEqual(kept.count, 3)
        XCTAssertFalse(kept.contains { cal.component(.day, from: $0.wake) == 24 })
    }

    func testUnskippingRestoresItAndOldSkipsAreForgotten() {
        var setup = PersonalSetup()
        setup.setSkipped(true, wake: date(20, 7), now: date(19, 12), calendar: cal)
        setup.setSkipped(true, wake: date(24, 7), now: date(22, 12), calendar: cal)
        XCTAssertEqual(setup.skippedReminderNights, ["2026-09-24"], "a past morning's skip is dropped")
        setup.setSkipped(false, wake: date(24, 7), now: date(22, 12), calendar: cal)
        XCTAssertNil(setup.skippedReminderNights)
    }

    /// A setup saved before the field existed still decodes.
    func testAnOlderSetupDecodes() throws {
        let data = try JSONEncoder().encode(PersonalSetup())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "skippedReminderNights")
        let decoded = try JSONDecoder().decode(PersonalSetup.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.skippedReminderNights)
    }
}

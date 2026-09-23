import XCTest

final class SchedulePreviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private var bed: Date { now.addingTimeInterval(3 * 3600) }
    private var wake: Date { bed.addingTimeInterval(8 * 3600) }
    private let everything = SchedulePreview.Settings(
        bedtimeReminders: true, wakeWindow: true, wakeAlarm: true, morningBrief: true,
        notificationsBlocked: false, alarmBlocked: false
    )

    /// Minutes relative to `now`, so assertions do not depend on a locale.
    private func text(_ date: Date) -> String { "T+\(Int(date.timeIntervalSince(now) / 60))" }

    private func lines(_ settings: SchedulePreview.Settings, bed: Date? = nil, skipped: Bool = false) -> [String] {
        SchedulePreview.lines(bed: bed ?? self.bed, wake: wake, settings: settings, isSkipped: skipped, now: now, timeText: text)
    }

    func testEverythingOnListsEachItemAtTheTimeTheSchedulerUses() {
        XCTAssertEqual(lines(everything), [
            "Wind-down notification at T+150.",
            "Bedtime notification at T+180.",
            "Wake window notification at T+640.",
            "Alarm rings at T+660, even in Silent mode.",
            "Morning brief notification at T+690."
        ])
    }

    func testAWindDownAlreadyPastIsSaidNotListed() {
        let soon = now.addingTimeInterval(10 * 60)
        let result = lines(everything, bed: soon)
        XCTAssertEqual(result.first, "Wind-down: not sent, T+-20 has already passed.")
        XCTAssertEqual(result[1], "Bedtime notification at T+10.")
    }

    func testBlockedPermissionsAreNamed() {
        var settings = everything
        settings.notificationsBlocked = true
        settings.alarmBlocked = true
        let result = lines(settings)
        XCTAssertTrue(result.allSatisfy { $0.contains("not sent") || $0.contains("not set") }, "\(result)")
        XCTAssertTrue(result.contains("Alarm: not set, Zoon does not have permission to set alarms."))
    }

    func testTheAlarmNeedsTheWakeWindowAsInTheScheduler() {
        var settings = everything
        settings.wakeWindow = false
        XCTAssertFalse(lines(settings).contains { $0.hasPrefix("Alarm") })
    }

    func testAllOffAndSkippedSaySoInsteadOfBeingBlank() {
        let off = SchedulePreview.Settings(
            bedtimeReminders: false, wakeWindow: false, wakeAlarm: true, morningBrief: false,
            notificationsBlocked: false, alarmBlocked: false
        )
        XCTAssertEqual(lines(off).count, 1)
        XCTAssertTrue(lines(off)[0].hasPrefix("Nothing will be scheduled"))
        XCTAssertEqual(lines(everything, skipped: true).count, 1)
        XCTAssertTrue(lines(everything, skipped: true)[0].contains("skipped"))
    }

    func testAPickedBedtimeAfterMidnightFallsOnTheMorningNotTheEveningBefore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        // The picker's dates keep the evening's day; only the clock matters.
        let bedClock = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 1, minute: 15))!
        let wakeClock = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 8))!
        let resolved = SchedulePreview.resolve(bedClock: bedClock, wakeClock: wakeClock, morning: morning, calendar: calendar)
        XCTAssertEqual(resolved.bed, calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 1, minute: 15)))
        XCTAssertEqual(resolved.wake, calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 8)))

        let eveningBed = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23))!
        XCTAssertEqual(
            SchedulePreview.resolve(bedClock: eveningBed, wakeClock: wakeClock, morning: morning, calendar: calendar).bed,
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23))
        )
    }
}

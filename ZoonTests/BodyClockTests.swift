import XCTest

final class BodyClockTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    /// Midpoint 23:45 (-0.25, signed convention), 8-hour typical duration:
    /// onsetHour = -4.25 (19:45), wakeHour = +3.75 (03:45).
    private let typical = BodyClock(midpoint: -0.25, spreadHours: 0.3, nightCount: 21, typicalDurationMinutes: 480)

    /// `window(for:)` must return the night beginning on `date`'s own
    /// evening, per its doc comment -- not the previous day's evening. This
    /// pins the exact bug a V6 screenshot caught: BodyClockView showed an
    /// "alignment" score of 0 with "Your sleep started about 1407 minutes
    /// later than your recent preferred timing" for an ordinary night,
    /// because `window(for:)` anchored the (negative, evening) onset hour to
    /// `date`'s own midnight instead of the following one, landing the
    /// window a full day before the actual bedtime it was being compared
    /// against.
    func testWindowBeginsOnTheEveningOfTheGivenDate() throws {
        let window = typical.window(for: date(2026, 3, 10, 15))
        let onset = try XCTUnwrap(window?.start)
        let wake = try XCTUnwrap(window?.end)

        XCTAssertEqual(calendar.component(.day, from: onset), 10, "onset should fall on the 10th, not the 9th")
        XCTAssertEqual(calendar.component(.hour, from: onset), 19)
        XCTAssertEqual(calendar.component(.minute, from: onset), 45)

        XCTAssertEqual(calendar.component(.day, from: wake), 11, "wake should fall on the 11th, the morning after")
        XCTAssertEqual(calendar.component(.hour, from: wake), 3)
        XCTAssertEqual(calendar.component(.minute, from: wake), 45)
    }

    /// A bedtime right in the middle of the estimated window must read as
    /// (near) zero drift -- the case the 1407-minute bug got wildly wrong.
    func testDriftOfAnOrdinaryOnTimeBedtimeIsSmall() throws {
        let bedtime = date(2026, 3, 10, 19, 50) // 5 minutes after the 19:45 onset
        let drift = try XCTUnwrap(typical.drift(of: bedtime))
        XCTAssertEqual(drift, 5, accuracy: 1)
    }

    /// A bedtime a real hour later than usual should read as a real hour of
    /// drift -- not off by a day's worth of minutes.
    func testDriftOfALateBedtimeIsPlausible() throws {
        let bedtime = date(2026, 3, 10, 20, 45) // one hour after the 19:45 onset
        let drift = try XCTUnwrap(typical.drift(of: bedtime))
        XCTAssertEqual(drift, 60, accuracy: 1)
    }

    /// A night-owl whose entire window sits after midnight (onsetHour
    /// positive) is the one case where anchoring to the *next* midnight
    /// still has to land the window on the right calendar night.
    func testWindowHandlesAnOnsetThatFallsAfterMidnight() throws {
        // Midpoint 05:00 (+5), 8-hour duration: onsetHour +1 (01:00), wakeHour +9 (09:00).
        let nightOwl = BodyClock(midpoint: 5, spreadHours: 0.3, nightCount: 21, typicalDurationMinutes: 480)
        let window = nightOwl.window(for: date(2026, 3, 10, 15))
        let onset = try XCTUnwrap(window?.start)
        let wake = try XCTUnwrap(window?.end)

        XCTAssertEqual(calendar.component(.day, from: onset), 11, "a post-midnight onset for the night of the 10th falls on the 11th")
        XCTAssertEqual(calendar.component(.hour, from: onset), 1)
        XCTAssertEqual(calendar.component(.day, from: wake), 11)
        XCTAssertEqual(calendar.component(.hour, from: wake), 9)
    }
}

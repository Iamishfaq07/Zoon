import XCTest

@MainActor
final class NapStoreTests: XCTestCase {

    private func makeStore() -> NapStore {
        let defaults = UserDefaults(suiteName: "com.zoon.sleep.tests.naps.\(UUID().uuidString)")!
        return NapStore(defaults: defaults)
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// The actual bug: `minutesBefore(night:)` used to always read "the day
    /// before" in `Calendar.current` -- the device's timezone right now,
    /// not the timezone the night itself was recorded in. This nap sits at
    /// 07:30 UTC on Jan 15, which is already the 15th in New York
    /// (02:30 EST) but still the 14th in Los Angeles (23:30 PST the day
    /// before). Crediting it to "the day before a Jan 16 night" therefore
    /// depends entirely on which timezone does the reading: it should count
    /// in New York and not count in Los Angeles, for the exact same nap and
    /// the exact same "night."
    func testMinutesBeforeAttributesTheNapToTheRightCalendarDayPerTimeZone() {
        let store = makeStore()
        let napStart = utc(2024, 1, 15, 7, 30)
        store.importNaps([NapStore.Nap(start: napStart, end: napStart.addingTimeInterval(20 * 60))])

        let night = utc(2024, 1, 16, 12, 0)
        let newYork = TimeZone(identifier: "America/New_York")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

        XCTAssertEqual(store.minutesBefore(night: night, timeZone: newYork), 20, accuracy: 0.01)
        XCTAssertEqual(store.minutesBefore(night: night, timeZone: losAngeles), 0, accuracy: 0.01)
    }
}

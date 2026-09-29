import XCTest

final class SnoreHabitLinkTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func day(_ n: Int) -> Date {
        calendar.startOfDay(for: t0.addingTimeInterval(Double(n) * 86_400))
    }

    func testAlcoholNightsSnoringMoreAreFound() {
        let percents: [Double] = [25, 22, 28, 20, 8, 10, 6, 9, 7]
        let nights = percents.enumerated().map { SnoreHabitLink.Night(day: day($0.offset), snorePercent: $0.element) }
        var tags: [Date: Set<String>] = [:]
        for i in 0..<4 { tags[day(i)] = ["alcohol"] }
        for i in 4..<9 { tags[day(i)] = [] }
        let links = SnoreHabitLink.links(nights: nights, tagsByDay: tags)
        XCTAssertEqual(links.first?.tag, "alcohol")
        XCTAssertEqual(links.first?.withNights, 4)
        XCTAssertEqual(links.first?.withoutNights, 5)
        XCTAssertEqual(links.first?.withPercent ?? 0, 23.75, accuracy: 0.001)
        XCTAssertEqual(links.first?.withoutPercent ?? 0, 8, accuracy: 0.001)
    }

    func testNightsWithoutAJournalEntryAreOnNeitherSide() {
        let nights = (0..<10).map { SnoreHabitLink.Night(day: day($0), snorePercent: $0 < 3 ? 30 : 5) }
        // Only the three alcohol nights have entries: nothing to compare with.
        var tags: [Date: Set<String>] = [:]
        for i in 0..<3 { tags[day(i)] = ["alcohol"] }
        XCTAssertTrue(SnoreHabitLink.links(nights: nights, tagsByDay: tags).isEmpty)
    }

    func testTooFewNightsOrTooSmallAGapIsNotShown() {
        let nights = (0..<8).map { SnoreHabitLink.Night(day: day($0), snorePercent: $0 < 4 ? 12 : 10) }
        var tags: [Date: Set<String>] = [:]
        for i in 0..<8 { tags[day(i)] = i < 4 ? ["lateMeal"] : [] }
        XCTAssertTrue(SnoreHabitLink.links(nights: nights, tagsByDay: tags).isEmpty, "2 points is noise")

        let few = (0..<5).map { SnoreHabitLink.Night(day: day($0), snorePercent: $0 < 2 ? 40 : 5) }
        var fewTags: [Date: Set<String>] = [:]
        for i in 0..<5 { fewTags[day(i)] = i < 2 ? ["alcohol"] : [] }
        XCTAssertTrue(SnoreHabitLink.links(nights: few, tagsByDay: fewTags).isEmpty, "two nights is not a pattern")
    }

    func testLessSnoringIsReportedToo() {
        let nights = (0..<8).map { SnoreHabitLink.Night(day: day($0), snorePercent: $0 < 4 ? 4 : 16) }
        var tags: [Date: Set<String>] = [:]
        for i in 0..<8 { tags[day(i)] = i < 4 ? ["coolRoom"] : [] }
        let link = SnoreHabitLink.links(nights: nights, tagsByDay: tags).first
        XCTAssertEqual(link?.tag, "coolRoom")
        XCTAssertEqual(link?.difference ?? 0, -12, accuracy: 0.001)
    }
}

import XCTest

/// Covers the matched-control rebuild.
///
/// The version this replaces had no control group. It compared nap days
/// against a fixed 35% threshold, or against *other nap days*, and never once
/// against a day without a nap — so every association it reported was one it
/// had not measured. It also bucketed everything under thirty-five minutes
/// together and labelled the group "your 20–30 minute naps", and it read
/// bedtime as a raw hour, so 23:50 and 00:10 scored as six hours apart.
final class NapLearningTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// Weekday dates only, so the weekend hard constraint never blocks a
    /// match in tests that are not about it.
    private func weekday(_ index: Int) -> Date {
        // 2026-09-14 is a Monday. Five weekdays, skip two, repeat.
        let offset = (index / 5) * 7 + (index % 5)
        return calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 14)
        )!.addingTimeInterval(Double(offset) * 86_400)
    }

    private func day(
        _ index: Int,
        nap: NapLearning.Observation.Nap? = nil,
        bedtimeMinutes: Double = -60,
        priorAsleep: Double? = 450,
        shortfall: Double? = 30,
        isWeekend: Bool = false,
        timeZone: String = "UTC"
    ) -> NapLearning.Observation {
        NapLearning.Observation(
            date: weekday(index),
            nap: nap,
            bedtimeMinutes: bedtimeMinutes,
            latencyMinutes: 12,
            nextAsleepMinutes: 440,
            isWeekend: isWeekend,
            priorNightAsleepMinutes: priorAsleep,
            shortfallMinutes: shortfall,
            timeZoneIdentifier: timeZone
        )
    }

    /// `napMinutes`/`napHour` nil builds a control day.
    private func series(
        napDays: Int,
        controlDays: Int,
        napMinutes: Double,
        napHour: Double,
        napBedtimeMinutes: Double = -60,
        controlBedtimeMinutes: Double = -60
    ) -> [NapLearning.Observation] {
        var out: [NapLearning.Observation] = []
        for index in 0..<napDays {
            out.append(day(
                index,
                nap: .init(startHour: napHour, minutes: napMinutes),
                bedtimeMinutes: napBedtimeMinutes
            ))
        }
        for index in 0..<controlDays {
            out.append(day(napDays + index, bedtimeMinutes: controlBedtimeMinutes))
        }
        return out
    }

    // MARK: - Nothing is claimed without a control group

    func testInsufficientNapHistoryIsHonest() {
        let findings = NapLearning.findings(from: [
            day(0, nap: .init(startHour: 13, minutes: 20))
        ])
        XCTAssertEqual(findings.first?.confidence, .insufficient)
        XCTAssertNil(findings.first?.bucket)
    }

    /// The failure the rebuild exists for: plenty of naps, nothing to compare
    /// them against. The old engine reported findings here.
    func testNapsWithoutControlDaysClaimNothing() throws {
        let findings = NapLearning.findings(
            from: series(napDays: 10, controlDays: 2, napMinutes: 22, napHour: 13.5)
        )
        let finding = try XCTUnwrap(findings.first)
        XCTAssertEqual(finding.confidence, .insufficient)
        XCTAssertNil(finding.medianBedtimeShiftMinutes)
        XCTAssertTrue(finding.sentence.contains("without a nap"), finding.sentence)
    }

    // MARK: - Buckets mean what they say

    /// A five-minute doze and a deliberate half-hour are not the same event.
    func testShortAndBriefNapsAreDifferentBuckets() {
        XCTAssertEqual(NapLearning.Duration.forMinutes(5), .brief)
        XCTAssertEqual(NapLearning.Duration.forMinutes(22), .short)
        XCTAssertEqual(NapLearning.Duration.forMinutes(50), .long)
    }

    /// And the label names the range actually measured, which the sentence
    /// this replaced did not.
    func testTheSentenceNamesTheBucketItMeasured() throws {
        let findings = NapLearning.findings(
            from: series(napDays: 8, controlDays: 10, napMinutes: 22, napHour: 13.5)
        )
        let finding = try XCTUnwrap(findings.first { $0.bucket?.duration == .short })
        XCTAssertTrue(finding.sentence.contains("15–35 minute naps"), finding.sentence)
        XCTAssertTrue(finding.sentence.contains("before 3 PM"), finding.sentence)
    }

    func testABriefDozeIsNotReportedAsAShortNap() {
        let findings = NapLearning.findings(
            from: series(napDays: 8, controlDays: 10, napMinutes: 6, napHour: 13.5)
        )
        XCTAssertNil(findings.first { $0.bucket?.duration == .short })
        XCTAssertNotNil(findings.first { $0.bucket?.duration == .brief })
    }

    // MARK: - The measurement

    /// Same bedtime on nap days and control days: no shift, said plainly.
    func testNoShiftIsReportedAsNoShift() throws {
        let findings = NapLearning.findings(
            from: series(napDays: 8, controlDays: 10, napMinutes: 22, napHour: 13.5)
        )
        let finding = try XCTUnwrap(findings.first { $0.bucket?.duration == .short })
        XCTAssertEqual(try XCTUnwrap(finding.medianBedtimeShiftMinutes), 0, accuracy: 0.001)
        XCTAssertTrue(finding.sentence.contains("close to your normal window"), finding.sentence)
    }

    /// Long evening naps followed by bedtimes an hour later.
    func testALaterBedtimeIsReportedAsAnAssociationNotACause() throws {
        let findings = NapLearning.findings(
            from: series(
                napDays: 8, controlDays: 10, napMinutes: 60, napHour: 18,
                napBedtimeMinutes: 0, controlBedtimeMinutes: -60
            )
        )
        let finding = try XCTUnwrap(findings.first { $0.bucket?.duration == .long })
        XCTAssertEqual(try XCTUnwrap(finding.medianBedtimeShiftMinutes), 60, accuracy: 0.001)
        XCTAssertTrue(finding.sentence.contains("associated with"), finding.sentence)
        XCTAssertTrue(finding.sentence.contains("not a cause"), finding.sentence)
        XCTAssertFalse(finding.sentence.lowercased().contains("caused"), finding.sentence)
    }

    /// Bedtime is circular. 23:50 against 00:10 is twenty minutes, not
    /// twenty-three hours and forty.
    func testBedtimeShiftIsMeasuredOnTheCircle() throws {
        let findings = NapLearning.findings(
            from: series(
                napDays: 8, controlDays: 10, napMinutes: 22, napHour: 13.5,
                // 00:10 on the shifted scale is +10; 23:50 is −10.
                napBedtimeMinutes: 10, controlBedtimeMinutes: -10
            )
        )
        let finding = try XCTUnwrap(findings.first { $0.bucket?.duration == .short })
        XCTAssertEqual(try XCTUnwrap(finding.medianBedtimeShiftMinutes), 20, accuracy: 0.001)
        // Twenty minutes clears the threshold, but only just, and the
        // sentence names the magnitude in minutes rather than hours.
        XCTAssertTrue(finding.sentence.contains("20m"), finding.sentence)
        XCTAssertFalse(finding.sentence.contains("0h"), finding.sentence)
    }

    /// A shift smaller than the most a bedtime may deliberately move in one
    /// night is not an association worth naming.
    func testATinyShiftIsNotNamed() throws {
        let findings = NapLearning.findings(
            from: series(
                napDays: 8, controlDays: 10, napMinutes: 22, napHour: 13.5,
                napBedtimeMinutes: -50, controlBedtimeMinutes: -60
            )
        )
        let finding = try XCTUnwrap(findings.first { $0.bucket?.duration == .short })
        XCTAssertTrue(finding.sentence.contains("close to your normal window"), finding.sentence)
    }

    // MARK: - Matching

    /// Without replacement: eight nap days and two control days cannot
    /// produce eight pairs.
    func testControlDaysAreNotReused() {
        let findings = NapLearning.findings(
            from: series(napDays: 8, controlDays: 3, napMinutes: 22, napHour: 13.5)
        )
        // Three controls is below the sample floor, so nothing is reported
        // rather than three pairs being stretched into eight.
        XCTAssertEqual(findings.first?.confidence, .insufficient)
    }

    /// A weekend day is not a comparison for a working one.
    func testWeekendDaysAreNotMatchedAgainstWeekdays() {
        var days: [NapLearning.Observation] = (0..<8).map {
            day($0, nap: .init(startHour: 13.5, minutes: 22), isWeekend: false)
        }
        days += (0..<10).map { day(8 + $0, isWeekend: true) }
        let findings = NapLearning.findings(from: days)
        XCTAssertNil(findings.first { $0.bucket != nil })
    }

    /// A day in another timezone is a travel day whatever else it was.
    func testTravelDaysAreNotUsedAsControls() {
        var days: [NapLearning.Observation] = (0..<8).map {
            day($0, nap: .init(startHour: 13.5, minutes: 22))
        }
        days += (0..<10).map { day(8 + $0, timeZone: "Asia/Tokyo") }
        let findings = NapLearning.findings(from: days)
        XCTAssertNil(findings.first { $0.bucket != nil })
    }

    /// The count reported is matched pairs, not naps: a nap with no
    /// comparable day behind it contributes nothing to the estimate.
    func testTheSampleCountIsPairsNotNaps() throws {
        let findings = NapLearning.findings(
            from: series(napDays: 8, controlDays: 10, napMinutes: 22, napHour: 13.5)
        )
        let finding = try XCTUnwrap(findings.first { $0.bucket != nil })
        XCTAssertEqual(finding.sampleCount, 8, "eight nap days, ten controls, eight pairs")
    }
}

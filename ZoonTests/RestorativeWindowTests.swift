import XCTest

/// `RestorativeWindow` is the first thing in the app that makes a positive
/// claim about a *stretch of the waking day*, which is a shape the rest of the
/// engines do not have: everything else is keyed to a night. Most of what
/// follows is therefore about the boundaries — what ends a run, what is too
/// short to be a window, and what the type refuses to say when the evidence
/// for it is not there.
final class RestorativeWindowTests: XCTestCase {

    /// 14:00 on a fixed day, so every case sits inside the same three-hour
    /// block and the block boundary is only in play where a test puts it
    /// there.
    private var origin: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 16
        components.hour = 14
        components.minute = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func bin(_ index: Int) -> Date {
        origin.addingTimeInterval(Double(index * RestorativeWindow.binMinutes) * 60)
    }

    /// A baseline whose afternoon block has a median of 70 and a spread of 4.
    /// `settledZ` of −0.5 puts the qualifying line at 67.03 bpm, so 64 is
    /// settled and 69 is not.
    private func baseline(median: Double = 70, spread: Double = 4) -> DaytimeBaseline {
        DaytimeBaseline(
            bins: (0..<DaytimeBaseline.binCount).map {
                DaytimeBaseline.Bin(
                    index: $0, median: median, spread: spread, sampleCount: 40, dayCount: 10
                )
            }
        )
    }

    private func heartRate(_ values: [Double?]) -> [RestorativeWindow.Sample] {
        values.enumerated().map { RestorativeWindow.Sample(date: bin($0.offset), value: $0.element) }
    }

    private func quietEnergy(_ count: Int, kcal: Double = 2) -> [RestorativeWindow.Sample] {
        (0..<count).map { RestorativeWindow.Sample(date: bin($0), value: kcal) }
    }

    // MARK: - Finding a window

    func testHalfAnHourBelowTheHourlyBaselineIsOneWindow() {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 6)),
            activeEnergy: quietEnergy(6),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.minutes, 30)
        XCTAssertEqual(windows.first?.medianHeartRate, 64)
        XCTAssertEqual(windows.first?.baselineHeartRate, 70)
        XCTAssertEqual(windows.first?.beatsBelowBaseline, 6)
    }

    /// Ten minutes is two bins. The brief's own example is 24 minutes; a
    /// couple of low readings is not a period of anything.
    func testTenMinutesIsTooShortToBeAWindow() {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 2)),
            activeEnergy: quietEnergy(2),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertTrue(windows.isEmpty)
    }

    func testFifteenMinutesExactlyQualifies() {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 3)),
            activeEnergy: quietEnergy(3),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.minutes, RestorativeWindow.minimumMinutes)
    }

    /// A reading at the baseline itself is an ordinary afternoon, not a
    /// settled one. The claim is "lower than your usual", and 70 is the usual.
    func testAReadingAtTheBaselineIsNotSettled() {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 70, count: 8)),
            activeEnergy: quietEnergy(8),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertTrue(windows.isEmpty)
    }

    // MARK: - What ends a run

    func testMovementInTheMiddleSplitsOneStretchIntoTwoWindows() {
        var energy = quietEnergy(7)
        energy[3] = RestorativeWindow.Sample(date: bin(3), value: 40)

        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 7)),
            activeEnergy: energy,
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.map(\.minutes), [15, 15])
    }

    /// Movement is a gate, and an absent energy reading is not a low one.
    /// "Do not invent data to avoid empty UI" applies to the inputs as much
    /// as to the output.
    func testAnAbsentMovementReadingDoesNotCountAsLowMovement() {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 8)),
            activeEnergy: [],
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertTrue(windows.isEmpty)
    }

    func testSleepAndWorkoutsAreExcludedOutright() {
        let asleep = DateInterval(start: bin(0), end: bin(8))
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 8)),
            activeEnergy: quietEnergy(8),
            baseline: baseline(),
            excluded: [asleep],
            calendar: utc
        )
        XCTAssertTrue(windows.isEmpty)
    }

    /// Two settled stretches with an hour of nothing between them are two
    /// windows. Joining them would report a window that covers time nobody
    /// measured.
    func testAGapInTheSeriesEndsTheRun() {
        let early = (0..<4).map { RestorativeWindow.Sample(date: bin($0), value: 64.0) }
        let late = (16..<20).map { RestorativeWindow.Sample(date: bin($0), value: 64.0) }
        let energy = (Array(0..<4) + Array(16..<20)).map {
            RestorativeWindow.Sample(date: bin($0), value: 2.0)
        }

        let windows = RestorativeWindow.windows(
            heartRate: early + late,
            activeEnergy: energy,
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.map(\.minutes), [20, 20])
    }

    func testARisingHeartRateEndsTheWindowWhereItRises() {
        let values: [Double?] = [64, 64, 64, 64, 72, 72]
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(values),
            activeEnergy: quietEnergy(6),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.minutes, 20)
        XCTAssertEqual(windows.first?.end, bin(4))
    }

    // MARK: - Coverage

    /// One missed reading is a watch, not the end of a period.
    func testASingleMissingReadingDoesNotEndTheWindow() {
        let values: [Double?] = [64, 64, nil, 64, 64, 64]
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(values),
            activeEnergy: quietEnergy(6),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.minutes, 30)
        XCTAssertEqual(windows.first?.coveredBins, 5)
        XCTAssertEqual(windows.first?.totalBins, 6)
    }

    /// Half a window of nothing is a gap with a reading either side, and the
    /// honest answer is to say nothing about it.
    func testHalfTheBinsMissingFailsTheCoverageGate() {
        let values: [Double?] = [64, nil, nil, nil, 64, 64]
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(values),
            activeEnergy: quietEnergy(6),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertTrue(windows.isEmpty)
    }

    /// The span a window claims must be the span it measured. Trailing blanks
    /// would make it longer and worse-covered than the settled stretch was.
    func testTrailingBlankBinsAreTrimmedFromTheSpan() throws {
        let values: [Double?] = [64, 64, 64, 64, nil, nil]
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(values),
            activeEnergy: quietEnergy(6),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(windows.count, 1)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(window.minutes, 20)
        XCTAssertEqual(window.coverage, 1, accuracy: 0.0001)
        XCTAssertEqual(window.confidence, .high)
    }

    func testConfidenceFollowsCoverage() {
        let values: [Double?] = [64, 64, nil, 64, 64, 64, 64, 64]
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(values),
            activeEnergy: quietEnergy(8),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(windows.first?.confidence, .moderate)
    }

    // MARK: - Refusals

    /// `DaytimeBaseline` drops a block until it has twelve samples across
    /// seven days. With no block there is no personal figure to compare
    /// against, and a fixed threshold would be a clock reading.
    func testNoQualifyingBaselineBlockMeansNoWindow() {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 8)),
            activeEnergy: quietEnergy(8),
            baseline: DaytimeBaseline(bins: []),
            calendar: utc
        )
        XCTAssertTrue(windows.isEmpty)
    }

    /// A block whose readings never move makes every reading extreme. Refuse
    /// rather than report a window off a degenerate denominator.
    func testADegenerateSpreadIsRefusedRatherThanDividedBy() {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 8)),
            activeEnergy: quietEnergy(8),
            baseline: baseline(spread: 0.1),
            calendar: utc
        )
        XCTAssertTrue(windows.isEmpty)
    }

    /// The summary refuses to say "no settled periods today", because that is
    /// also exactly what an empty HealthKit store looks like.
    func testTheSummaryIsSilentRatherThanReportingZero() {
        XCTAssertNil(RestorativeWindow.summary([]))
    }

    func testTheSummaryCountsPeriodsAndMinutes() {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 6)),
            activeEnergy: quietEnergy(6),
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(RestorativeWindow.summary(windows), "1 settled period today, 30 minutes in total.")
    }

    // MARK: - HRV corroborates, and never gates

    func testAWindowIsFoundWithNoHRVAtAllAndSaysSo() throws {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 6)),
            activeEnergy: quietEnergy(6),
            hrv: [],
            baseline: baseline(),
            calendar: utc
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertNil(windows.first?.medianHRV)
        XCTAssertEqual(windows.first?.hrvNote, "No HRV readings in this window.")
        XCTAssertFalse(try XCTUnwrap(windows.first?.evidence).contains("HRV"))
    }

    func testHRVIsReportedWhereItExists() throws {
        let hrv = [
            RestorativeWindow.Sample(date: bin(1), value: 58),
            RestorativeWindow.Sample(date: bin(3), value: 62)
        ]
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 6)),
            activeEnergy: quietEnergy(6),
            hrv: hrv,
            baseline: baseline(),
            calendar: utc
        )
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(window.medianHRV, 60)
        XCTAssertNil(window.hrvNote)
        XCTAssertTrue(window.evidence.contains("HRV 60 ms"))
    }

    // MARK: - Language

    /// The brief is explicit: do not call it meditation, do not infer
    /// psychological calm. This is the guard the rest of the app's copy
    /// already runs through, plus the two words this feature in particular
    /// must never reach for.
    func testTheCopyClaimsPhysiologyAndNothingAboutAMind() throws {
        let windows = RestorativeWindow.windows(
            heartRate: heartRate(Array(repeating: 64, count: 6)),
            activeEnergy: quietEnergy(6),
            hrv: [RestorativeWindow.Sample(date: bin(1), value: 58)],
            baseline: baseline(),
            calendar: utc
        )
        let window = try XCTUnwrap(windows.first)

        for line in [window.sentence, window.evidence, RestorativeWindow.summary(windows) ?? ""] {
            XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(line), line)
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(line), line)
            for banned in ["meditat", "calm", "relax", "stress-free", "mindful"] {
                XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
            }
        }
        XCTAssertEqual(window.sentence, "Your physiology was relatively settled during this period.")
    }
}

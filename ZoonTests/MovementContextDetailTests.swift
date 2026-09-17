import XCTest

/// §27's refinement: the measures the engine carried but never spoke, and the
/// line it must not cross.
///
/// The existing `MovementContextTests` cover the step comparison and are
/// untouched — the sentence logic did not change.
final class MovementContextDetailTests: XCTestCase {

    /// Monday.
    private let weekday = 2

    private func snapshot(
        steps: Int? = 5_000,
        typical: Int? = 6_000,
        activeEnergyKcal: Double? = nil,
        exerciseMinutes: Double? = nil,
        workoutCount: Int = 0
    ) -> MovementContext.Snapshot {
        MovementContext.snapshot(
            stepsSoFar: steps,
            typicalStepsByNow: typical,
            activeEnergyKcal: activeEnergyKcal,
            exerciseMinutes: exerciseMinutes,
            workoutCount: workoutCount,
            weekday: weekday
        )
    }

    // MARK: - The measures that were carried and discarded

    /// `activeEnergyKcal` was on the struct, visible to every caller, and part
    /// of no sentence — the builder had a literal `_ = activeEnergyKcal`.
    func testActiveEnergyNowReachesTheDetailLine() throws {
        let detail = try XCTUnwrap(snapshot(activeEnergyKcal: 412).detail)
        XCTAssertTrue(detail.contains("412 kcal active"), detail)
    }

    func testExerciseMinutesAndWorkoutsAreReported() throws {
        let detail = try XCTUnwrap(
            snapshot(activeEnergyKcal: 300, exerciseMinutes: 44, workoutCount: 2).detail
        )
        XCTAssertTrue(detail.contains("44 exercise minutes"), detail)
        XCTAssertTrue(detail.contains("2 workouts"), detail)
    }

    func testOneWorkoutIsSingular() throws {
        let detail = try XCTUnwrap(snapshot(workoutCount: 1).detail)
        XCTAssertTrue(detail.contains("1 workout"), detail)
        XCTAssertFalse(detail.contains("1 workouts"), detail)
    }

    // MARK: - Missing is not zero, applied to the new measures too

    /// A day with nothing but steps prints no inventory rather than a row of
    /// zeros. An unrecorded active-energy reading is not a still day.
    func testADayWithOnlyStepsHasNoDetailLine() {
        XCTAssertNil(snapshot().detail)
    }

    func testAnAbsentReadingIsOmittedRatherThanPrintedAsZero() throws {
        let detail = try XCTUnwrap(snapshot(activeEnergyKcal: 250, exerciseMinutes: nil).detail)
        XCTAssertTrue(detail.contains("250 kcal"), detail)
        XCTAssertFalse(detail.contains("exercise"), detail)
    }

    /// Zero workouts is a real observation — the store can say it positively —
    /// but "0 workouts" is noise next to two measures that were recorded.
    func testZeroWorkoutsIsNotWorthALine() throws {
        let detail = try XCTUnwrap(snapshot(activeEnergyKcal: 250, workoutCount: 0).detail)
        XCTAssertFalse(detail.contains("workout"), detail)
    }

    func testANegativeWorkoutCountIsClampedRatherThanPrinted() {
        XCTAssertEqual(snapshot(workoutCount: -3).workoutCount, 0)
    }

    // MARK: - The short line

    func testTheShortLineNamesTheDirectionAgainstTheUsualDay() throws {
        let lower = try XCTUnwrap(snapshot(steps: 3_000, typical: 6_000).shortLine)
        XCTAssertEqual(lower, "Today's movement has been lower than your usual Monday.")

        let higher = try XCTUnwrap(snapshot(steps: 9_000, typical: 6_000).shortLine)
        XCTAssertTrue(higher.contains("higher than your usual Monday"), higher)
    }

    func testASmallDifferenceReadsAsUsualRatherThanAsAChange() throws {
        let line = try XCTUnwrap(snapshot(steps: 6_100, typical: 6_000).shortLine)
        XCTAssertTrue(line.contains("about usual"), line)
    }

    /// "Movement has been typical" and "we do not know" must not read the
    /// same, so with no comparison there is no short line at all.
    func testNoComparisonMeansNoShortLineRatherThanAReassuringOne() {
        XCTAssertNil(snapshot(steps: 5_000, typical: nil).shortLine)
        XCTAssertNil(snapshot(steps: nil, typical: 6_000).shortLine)
    }

    // MARK: - The line §27 draws

    /// Distance is listed in the brief and deliberately not shown. On a phone
    /// it is derived from the same steps already reported, and printing both
    /// would show one measurement twice.
    func testDistanceIsRefusedWithItsReasonRatherThanSilentlyOmitted() {
        XCTAssertTrue(MovementContext.distanceNote.contains("estimated from the same steps"))
    }

    /// Nothing here may become a score input, and nothing here says what the
    /// movement means for sleep.
    func testMovementDescribesTheDayAndNeverScoresIt() throws {
        let full = snapshot(
            steps: 3_000, typical: 12_000,
            activeEnergyKcal: 120, exerciseMinutes: 4, workoutCount: 0
        )
        var lines = [full.sentence, full.provenance]
        lines.append(full.detail ?? "")
        lines.append(full.shortLine ?? "")

        for line in lines {
            XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(line), line)
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(line), line)
            for banned in ["recovery", "sleep score", "readiness", "you should", "will sleep"] {
                XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
            }
        }
    }
}

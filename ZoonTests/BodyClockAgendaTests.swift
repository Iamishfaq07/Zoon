import XCTest

/// The named moments of a day.
///
/// "Awake" is true of fourteen hours and tells a reader nothing about which
/// one their finger is on. These tests are mostly about the two ways naming
/// a moment can lie: putting it at the wrong time, and naming a time that
/// isn't one.
final class BodyClockAgendaTests: XCTestCase {

    /// Midnight-centred sleep: onset 23:00 (signed -1), wake 07:00.
    private var bodyClock: BodyClock {
        BodyClock(midpoint: 3, spreadHours: 0.5, nightCount: 21, typicalDurationMinutes: 480)
    }

    private func mark(_ kind: EnergyForecast.Window.Kind, atHour hour: Int) -> EnergyForecast.Window {
        let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return EnergyForecast.Window(
            kind: kind,
            time: base.addingTimeInterval(Double(hour) * 3600)
        )
    }

    private var agenda: [BodyClockAgenda.Moment] {
        BodyClockAgenda.moments(
            bodyClock: bodyClock,
            energyMarks: [mark(.morningPeak, atHour: 10), mark(.afternoonDip, atHour: 14)]
        )
    }

    // MARK: - When each moment is

    func testWakeSitsAtTheBodyClockWakeHour() throws {
        let wake = try XCTUnwrap(agenda.first { $0.kind == .wake })
        XCTAssertEqual(wake.hour, 7, accuracy: 0.001)
    }

    /// `BodyClock` uses a signed convention where an 11pm onset is -1. That
    /// is correct arithmetic and wrong as a clock reading.
    func testAnEveningBedtimeWrapsToAClockHour() throws {
        let bedtime = try XCTUnwrap(agenda.first { $0.kind == .usualBedtime })
        XCTAssertEqual(bedtime.hour, 23, accuracy: 0.001)
    }

    /// The window's length comes from `LightCoach`, not a second copy of
    /// the number, so the dial and the Light card cannot disagree about
    /// when it closes.
    func testTheLightWindowClosesWhereLightCoachSaysItDoes() throws {
        let light = try XCTUnwrap(agenda.first { $0.kind == .lightWindow })
        XCTAssertEqual(light.hour, 7 + LightCoach.morningWindowMinutes / 60, accuracy: 0.001)
    }

    func testEveryEnergyMarkBecomesAMoment() {
        let energy = agenda.filter { $0.kind == .energy }
        XCTAssertEqual(energy.count, 2)
        XCTAssertEqual(energy.map(\.hour).sorted(), [10, 14])
    }

    /// The list reads as a day. Sorting by hour rather than by kind means an
    /// unusually late wake sits where it actually falls.
    func testMomentsAreInClockOrder() {
        XCTAssertEqual(agenda.map(\.hour), agenda.map(\.hour).sorted())
    }

    // MARK: - What the finger is on

    func testAFingerOnAMomentSelectsIt() throws {
        let selected = try XCTUnwrap(
            BodyClockAgenda.moment(atFraction: 10.0 / 24, in: agenda)
        )
        XCTAssertEqual(selected.label, EnergyForecast.Window.Kind.morningPeak.label)
    }

    /// Most of the day is not a named moment. Labelling 3pm "afternoon dip"
    /// because it is the closest thing on the list would be a claim the
    /// forecast never made.
    func testAFingerOnNothingSelectsNothing() {
        // 04:00 -- an hour from nothing on this agenda.
        XCTAssertNil(BodyClockAgenda.moment(atFraction: 4.0 / 24, in: agenda))
    }

    func testTheNearestMomentWinsWhenTwoAreInRange() throws {
        let close = [
            BodyClockAgenda.Moment(hour: 10, kind: .energy, label: "Peak", symbol: "sun.max", detail: ""),
            BodyClockAgenda.Moment(hour: 10.4, kind: .energy, label: "Other", symbol: "sun.max", detail: "")
        ]
        let selected = try XCTUnwrap(
            BodyClockAgenda.moment(atFraction: 10.3 / 24, in: close)
        )
        XCTAssertEqual(selected.label, "Other")
    }

    /// 23:30 and 00:30 are one hour apart, not twenty-three.
    func testSelectionWrapsAroundMidnight() throws {
        // Usual bedtime is 23:00; a finger at 23:20 is twenty minutes away.
        let selected = try XCTUnwrap(
            BodyClockAgenda.moment(atFraction: 23.34 / 24, in: agenda)
        )
        XCTAssertEqual(selected.kind, .usualBedtime)
    }

    func testCircularDistanceWrapsAtMidnight() {
        XCTAssertEqual(BodyClockAgenda.circularHourDistance(23.5, 0.5), 1, accuracy: 0.001)
        XCTAssertEqual(BodyClockAgenda.circularHourDistance(1, 13), 12, accuracy: 0.001)
    }

    // MARK: - Position on the dial

    func testFractionPlacesAMomentOnTheDial() {
        let noon = BodyClockAgenda.Moment(hour: 12, kind: .energy, label: "x", symbol: "sun.max", detail: "")
        XCTAssertEqual(BodyClockAgenda.fraction(of: noon), 0.5, accuracy: 0.001)
    }

    /// Every moment carries the sentence that says what it is for. An
    /// unexplained named time is a number with a label on it.
    func testEveryMomentExplainsItself() {
        for moment in agenda {
            XCTAssertFalse(moment.detail.isEmpty, "\(moment.label) has no explanation")
            XCTAssertFalse(moment.label.isEmpty)
            XCTAssertFalse(moment.symbol.isEmpty)
        }
    }
}

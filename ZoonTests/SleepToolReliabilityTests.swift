import XCTest

final class SleepToolReliabilityTests: XCTestCase {

    func testEmptyInputsProduceNoLines() {
        XCTAssertTrue(
            SleepToolReliability.lines(
                snoreMonitoredMinutes: nil,
                snoreGapMinutes: nil,
                snoreInterruptions: nil,
                snorePartial: false,
                napMinutes: nil,
                napWake: nil,
                soundsMinutes: nil,
                soundsUninterrupted: nil
            ).isEmpty
        )
    }

    func testSnoreAndNapCopyIsTroubleshootingNotAScore() {
        let lines = SleepToolReliability.lines(
            snoreMonitoredMinutes: 402,
            snoreGapMinutes: 18,
            snoreInterruptions: 1,
            snorePartial: false,
            napMinutes: 20,
            napWake: .alarmKit,
            soundsMinutes: 134,
            soundsUninterrupted: true
        )
        XCTAssertEqual(lines.map(\.title), ["Sleep Sounds", "Snore Check", "Nap"])
        XCTAssertEqual(lines[0].detail, "134m uninterrupted")
        XCTAssertEqual(lines[1].detail, "402m monitored · 1 interruption · 18m gap")
        XCTAssertTrue(lines[2].detail.contains("AlarmKit"))
        XCTAssertFalse(lines.contains { $0.detail.lowercased().contains("score") })
    }
}

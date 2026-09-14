import XCTest

final class NapLearningTests: XCTestCase {

    func testInsufficientHistoryIsHonest() {
        let findings = NapLearning.findings(from: [
            NapLearning.Observation(napStartHour: 13, napMinutes: 20, bedtimeHour: 23.2, latencyMinutes: 14, nextAsleepMinutes: 430, nextRecoveryPercent: 70)
        ])
        XCTAssertEqual(findings.first?.confidence, .insufficient)
        XCTAssertTrue(findings.first?.sentence.contains("1") == true)
    }

    func testShortAfternoonNapsAreNotClaimedToShiftBedtime() {
        let naps = (0..<8).map { _ in
            NapLearning.Observation(
                napStartHour: 13.5,
                napMinutes: 22,
                bedtimeHour: 23.1,
                latencyMinutes: 12,
                nextAsleepMinutes: 430,
                nextRecoveryPercent: 74
            )
        }
        let findings = NapLearning.findings(from: naps)
        XCTAssertTrue(findings.contains { $0.sentence.lowercased().contains("have not usually") })
        XCTAssertFalse(findings.contains { $0.sentence.lowercased().contains("cause") && !$0.sentence.lowercased().contains("not a cause") })
    }

    func testLongEveningNapsUseAssociationWording() {
        var naps: [NapLearning.Observation] = (0..<8).map { _ in
            NapLearning.Observation(
                napStartHour: 17,
                napMinutes: 70,
                bedtimeHour: 0.4,
                latencyMinutes: 40,
                nextAsleepMinutes: 400,
                nextRecoveryPercent: 60
            )
        }
        naps += (0..<8).map { _ in
            NapLearning.Observation(
                napStartHour: 13,
                napMinutes: 20,
                bedtimeHour: 23,
                latencyMinutes: 12,
                nextAsleepMinutes: 440,
                nextRecoveryPercent: 75
            )
        }
        let findings = NapLearning.findings(from: naps)
        XCTAssertTrue(findings.contains { $0.sentence.lowercased().contains("alongside") })
        XCTAssertTrue(findings.contains { $0.sentence.lowercased().contains("not a cause") })
    }
}

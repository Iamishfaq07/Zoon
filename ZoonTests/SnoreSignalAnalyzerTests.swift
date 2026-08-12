import Foundation
import XCTest

final class SnoreSignalAnalyzerTests: XCTestCase {

    func testLowFrequencyToneRetainsMostEnergy() {
        let samples = sineWave(frequency: 180, sampleRate: 48_000, duration: 0.1)
        let energy = samples.withUnsafeBufferPointer {
            SnoreSignalAnalyzer.energy(samples: $0, sampleRate: 48_000)
        }

        XCTAssertGreaterThan(energy.broadbandRMS, 0.01)
        XCTAssertGreaterThan(energy.lowFrequencyRatio, 0.65)
    }

    func testHighFrequencyToneIsRejectedByBandEnergy() {
        let samples = sineWave(frequency: 4_000, sampleRate: 48_000, duration: 0.1)
        let energy = samples.withUnsafeBufferPointer {
            SnoreSignalAnalyzer.energy(samples: $0, sampleRate: 48_000)
        }

        XCTAssertGreaterThan(energy.broadbandRMS, 0.01)
        XCTAssertLessThan(energy.lowFrequencyRatio, 0.35)
    }

    func testSilenceProducesNoRatio() {
        let samples = Array(repeating: Float.zero, count: 4_800)
        let energy = samples.withUnsafeBufferPointer {
            SnoreSignalAnalyzer.energy(samples: $0, sampleRate: 48_000)
        }

        XCTAssertEqual(energy.broadbandRMS, 0)
        XCTAssertEqual(energy.lowFrequencyRatio, 0)
    }

    private func sineWave(
        frequency: Double,
        sampleRate: Double,
        duration: Double
    ) -> [Float] {
        let count = Int(sampleRate * duration)
        return (0..<count).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.1)
        }
    }
}

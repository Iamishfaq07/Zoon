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

    func testALowHarmonicSoundIsPeriodicLowPitchedAndCrossesZeroRarely() {
        // A snore-like buzz: 110 Hz with two harmonics.
        let count = 4_800
        let samples: [Float] = (0..<count).map { i in
            let t = Double(i) / 48_000
            return Float(0.08 * sin(2 * .pi * 110 * t) + 0.04 * sin(2 * .pi * 220 * t) + 0.02 * sin(2 * .pi * 330 * t))
        }
        let frame = samples.withUnsafeBufferPointer { SnoreSignalAnalyzer.frame(samples: $0, sampleRate: 48_000) }
        XCTAssertEqual(frame.duration, 0.1, accuracy: 0.0001)
        XCTAssertGreaterThan(frame.periodicity, 0.6)
        XCTAssertGreaterThan(frame.lowRatio, 0.6)
        XCTAssertLessThan(frame.zeroCrossingRate, 1_500)
        XCTAssertGreaterThan(frame.levelDB, -30)
    }

    func testNoiseIsNotPeriodicAndCrossesZeroOften() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        let samples: [Float] = (0..<4_800).map { _ in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: seed >> 11) % 2_000 - 1_000) / 20_000
        }
        let frame = samples.withUnsafeBufferPointer { SnoreSignalAnalyzer.frame(samples: $0, sampleRate: 48_000) }
        XCTAssertLessThan(frame.periodicity, 0.4)
        XCTAssertGreaterThan(frame.zeroCrossingRate, 5_000)
    }

    func testSilenceIsTheFloorOfTheScale() {
        let samples = Array(repeating: Float.zero, count: 4_800)
        let frame = samples.withUnsafeBufferPointer { SnoreSignalAnalyzer.frame(samples: $0, sampleRate: 48_000) }
        XCTAssertEqual(frame.levelDB, -120, accuracy: 0.001)
        XCTAssertEqual(frame.periodicity, 0)
        XCTAssertEqual(frame.zeroCrossingRate, 0)
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

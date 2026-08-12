import Foundation

/// Small, deterministic signal feature used by `SnoreDetector`.
///
/// This is deliberately not a classifier. It measures how much of a buffer's
/// energy sits in a broad 60–700 Hz band, which is enough to reject many sharp
/// high-frequency sounds before the cadence heuristic runs. Keeping it pure
/// makes the claim testable without microphone hardware or stored audio.
enum SnoreSignalAnalyzer {

    struct Energy: Equatable, Sendable {
        let broadbandRMS: Float
        let lowFrequencyRMS: Float

        var lowFrequencyRatio: Float {
            guard broadbandRMS > 0 else { return 0 }
            return min(1, lowFrequencyRMS / broadbandRMS)
        }
    }

    static func energy(
        samples: UnsafeBufferPointer<Float>,
        sampleRate: Double
    ) -> Energy {
        guard !samples.isEmpty, sampleRate > 0 else {
            return Energy(broadbandRMS: 0, lowFrequencyRMS: 0)
        }

        let timeStep = 1 / sampleRate
        let highPassRC = 1 / (2 * Double.pi * 60)
        let lowPassRC = 1 / (2 * Double.pi * 700)
        let highPassAlpha = Float(highPassRC / (highPassRC + timeStep))
        let lowPassAlpha = Float(timeStep / (lowPassRC + timeStep))

        var previousInput: Float = 0
        var highPassed: Float = 0
        var bandPassed: Float = 0
        var broadbandSquares: Float = 0
        var bandSquares: Float = 0

        for sample in samples {
            broadbandSquares += sample * sample

            // First-order high-pass followed by a first-order low-pass. The
            // filters are intentionally cheap because this runs ten times a
            // second all night; cadence and confidence remain responsible for
            // the final estimate rather than pretending this is a diagnosis.
            highPassed = highPassAlpha * (highPassed + sample - previousInput)
            previousInput = sample
            bandPassed += lowPassAlpha * (highPassed - bandPassed)
            bandSquares += bandPassed * bandPassed
        }

        let count = Float(samples.count)
        return Energy(
            broadbandRMS: (broadbandSquares / count).squareRoot(),
            lowFrequencyRMS: (bandSquares / count).squareRoot()
        )
    }
}

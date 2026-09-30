import Foundation

/// Small, deterministic signal features used by `SnoreDetector`.
///
/// This is deliberately not a classifier. It describes each buffer -- its
/// level, how much of its energy sits in a broad 60–700 Hz band, how often it
/// crosses zero, and how periodic it is -- and `SnoreAcousticEngine` judges
/// shape and rhythm from those numbers. Keeping it pure makes every claim
/// testable without microphone hardware or stored audio.
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

    /// Everything `SnoreAcousticEngine` needs from one buffer, in one pass:
    /// level, low-band share, zero-crossing rate and periodicity.
    ///
    /// Runs on the audio tap's thread ten times a second, all night, so it
    /// stays cheap: the band-passed signal is kept at roughly 8 kHz (every
    /// sixth sample at 48 kHz, which the 700 Hz low-pass already band-limits)
    /// and the periodicity search covers only the lags of a 40–300 Hz
    /// fundamental -- about 150 thousand multiply-adds a buffer.
    static func frame(
        samples: UnsafeBufferPointer<Float>,
        sampleRate: Double
    ) -> SnoreFrame {
        guard !samples.isEmpty, sampleRate > 0 else {
            return SnoreFrame(duration: 0, levelDB: -120, lowRatio: 0, zeroCrossingRate: 0, periodicity: 0)
        }

        let timeStep = 1 / sampleRate
        let highPassRC = 1 / (2 * Double.pi * 60)
        let lowPassRC = 1 / (2 * Double.pi * 700)
        let highPassAlpha = Float(highPassRC / (highPassRC + timeStep))
        let lowPassAlpha = Float(timeStep / (lowPassRC + timeStep))
        let decimation = max(1, Int(sampleRate / 8_000))

        var previousInput: Float = 0
        var highPassed: Float = 0
        var bandPassed: Float = 0
        var broadbandSquares: Float = 0
        var bandSquares: Float = 0
        var crossings = 0
        var wasPositive: Bool?
        var decimated: [Float] = []
        decimated.reserveCapacity(samples.count / decimation + 1)

        for (index, sample) in samples.enumerated() {
            broadbandSquares += sample * sample
            highPassed = highPassAlpha * (highPassed + sample - previousInput)
            previousInput = sample
            bandPassed += lowPassAlpha * (highPassed - bandPassed)
            bandSquares += bandPassed * bandPassed
            // Crossings of the DC-free signal; exact zeros keep the last sign.
            if highPassed != 0 {
                let positive = highPassed > 0
                if let was = wasPositive, was != positive { crossings += 1 }
                wasPositive = positive
            }
            if index % decimation == 0 { decimated.append(bandPassed) }
        }

        let count = Float(samples.count)
        let broadbandRMS = (broadbandSquares / count).squareRoot()
        let lowRMS = (bandSquares / count).squareRoot()
        let duration = Double(samples.count) / sampleRate
        return SnoreFrame(
            duration: duration,
            levelDB: 20 * log10(max(Double(broadbandRMS), 1e-6)),
            lowRatio: broadbandRMS > 0 ? min(1, Double(lowRMS / broadbandRMS)) : 0,
            zeroCrossingRate: duration > 0 ? Double(crossings) / duration : 0,
            periodicity: periodicity(
                decimated,
                sampleRate: sampleRate / Double(decimation),
                lowestHz: 40,
                highestHz: 300
            )
        )
    }

    /// The highest normalised autocorrelation of `signal` over the lags of a
    /// fundamental between `lowestHz` and `highestHz`, 0...1.
    ///
    /// Normalised per lag by the energy of both overlapping halves, so a
    /// signal that fades within the buffer is not penalised and a louder one
    /// is not favoured.
    static func periodicity(
        _ signal: [Float],
        sampleRate: Double,
        lowestHz: Double,
        highestHz: Double
    ) -> Double {
        let n = signal.count
        guard n > 8, sampleRate > 0, highestHz > lowestHz, lowestHz > 0 else { return 0 }
        let minLag = max(1, Int((sampleRate / highestHz).rounded(.down)))
        let maxLag = min(n / 2, Int((sampleRate / lowestHz).rounded(.up)))
        guard maxLag > minLag else { return 0 }

        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n {
            prefix[i + 1] = prefix[i] + Double(signal[i]) * Double(signal[i])
        }
        guard prefix[n] > 0 else { return 0 }

        var best = 0.0
        for lag in minLag...maxLag {
            var product = 0.0
            for i in 0..<(n - lag) {
                product += Double(signal[i]) * Double(signal[i + lag])
            }
            let head = prefix[n - lag]
            let tail = prefix[n] - prefix[lag]
            let norm = (head * tail).squareRoot()
            guard norm > 0 else { continue }
            best = max(best, product / norm)
        }
        return min(1, max(0, best))
    }
}

import Foundation

/// Interval-level fusion of classifier and heuristic snore evidence.
///
/// `max(classifierSeconds, heuristicSeconds)` undercounts when the two
/// sources catch different true intervals, and overstates when the heuristic
/// is noisy. Merge overlapping ranges; prefer the classifier inside overlap.
enum SnoreEvidenceFusion: Sendable {

    struct Interval: Equatable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var source: Source
        var confidence: Double

        enum Source: String, Sendable, Codable {
            case classifier
            case heuristic
            case both
        }

        var duration: TimeInterval { max(0, end - start) }
    }

    static func fuse(
        classifier: [(start: TimeInterval, end: TimeInterval, confidence: Double)],
        heuristic: [(start: TimeInterval, end: TimeInterval)]
    ) -> [Interval] {
        let classified = classifier.filter { $0.end > $0.start }
        let heuristicOnly = heuristic.filter { $0.end > $0.start }

        var tagged: [Interval] = classified.map {
            Interval(start: $0.start, end: $0.end, source: .classifier, confidence: clamp($0.confidence))
        }
        for h in heuristicOnly {
            var remaining: [(start: TimeInterval, end: TimeInterval)] = [(h.start, h.end)]
            for c in classified {
                remaining = remaining.flatMap { slice($0, subtracting: (c.start, c.end)) }
            }
            tagged.append(contentsOf: remaining.map {
                Interval(start: $0.start, end: $0.end, source: .heuristic, confidence: 0.4)
            })
        }
        for i in tagged.indices where tagged[i].source == .classifier {
            if heuristicOnly.contains(where: { overlaps(tagged[i], $0) }) {
                tagged[i].source = .both
                tagged[i].confidence = min(1, tagged[i].confidence + 0.05)
            }
        }
        return tagged.sorted { $0.start < $1.start }
    }

    /// Convenience for tests and older call sites that only have ranges.
    static func fuse(
        classifier: [(start: TimeInterval, end: TimeInterval)],
        heuristic: [(start: TimeInterval, end: TimeInterval)]
    ) -> [Interval] {
        fuse(
            classifier: classifier.map { ($0.start, $0.end, 0.8) },
            heuristic: heuristic
        )
    }

    static func snoreSeconds(from intervals: [Interval]) -> Double {
        merge(intervals.map { ($0.start, $0.end) }).reduce(0) { $0 + ($1.end - $1.start) }
    }

    static func merge(_ ranges: [(start: TimeInterval, end: TimeInterval)]) -> [(start: TimeInterval, end: TimeInterval)] {
        let sorted = ranges.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var out: [(start: TimeInterval, end: TimeInterval)] = []
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current.end = max(current.end, next.end)
            } else {
                out.append(current)
                current = next
            }
        }
        out.append(current)
        return out
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func overlaps(_ a: Interval, _ b: (start: TimeInterval, end: TimeInterval)) -> Bool {
        a.start < b.end && b.start < a.end
    }

    private static func slice(
        _ range: (start: TimeInterval, end: TimeInterval),
        subtracting other: (start: TimeInterval, end: TimeInterval)
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        if other.end <= range.start || other.start >= range.end { return [range] }
        var parts: [(start: TimeInterval, end: TimeInterval)] = []
        if other.start > range.start {
            parts.append((range.start, min(other.start, range.end)))
        }
        if other.end < range.end {
            parts.append((max(other.end, range.start), range.end))
        }
        return parts.filter { $0.end - $0.start > 0.05 }
    }
}

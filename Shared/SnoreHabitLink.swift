import Foundation

/// Snoring on nights you logged a behaviour against nights you logged
/// without it -- "on the 4 nights you logged alcohol, you snored 21% of the
/// time monitored; on the 6 without it, 8%".
///
/// Only nights with both a Snore Check session and a journal entry count.
/// A night with no journal entry says nothing about whether the behaviour
/// happened, so it is on neither side. A comparison needs
/// `minimumNightsEachSide` nights on each side and a gap of at least
/// `minimumDifference` points before it is shown: a pattern in the person's
/// own nights, worded as one, never as a cause.
enum SnoreHabitLink {

    struct Night: Equatable, Sendable {
        /// Start of the morning the night ended on: the key `SnoreStore` and
        /// the journal share.
        let day: Date
        /// Snoring as a share of the time monitored, 0...100.
        let snorePercent: Double
    }

    struct Link: Equatable, Sendable {
        /// The journal tag's raw identifier.
        let tag: String
        let withPercent: Double
        let withoutPercent: Double
        let withNights: Int
        let withoutNights: Int

        /// Percentage points: positive when snoring ran higher with the tag.
        var difference: Double { withPercent - withoutPercent }
    }

    static let minimumNightsEachSide = 3
    static let minimumDifference = 5.0

    /// - Parameters:
    ///   - nights: Snore Check nights.
    ///   - tagsByDay: journal tags per morning, for mornings that have an
    ///     entry (an empty set is an entry with nothing ticked).
    /// - Returns: links worth showing, largest gap first.
    static func links(nights: [Night], tagsByDay: [Date: Set<String>]) -> [Link] {
        let logged = nights.compactMap { night -> (night: Night, tags: Set<String>)? in
            tagsByDay[night.day].map { (night: night, tags: $0) }
        }
        let tags = Set(logged.flatMap { $0.tags })
        return tags.compactMap { tag -> Link? in
            let with = logged.filter { $0.tags.contains(tag) }.map { $0.night.snorePercent }
            let without = logged.filter { !$0.tags.contains(tag) }.map { $0.night.snorePercent }
            guard with.count >= minimumNightsEachSide, without.count >= minimumNightsEachSide else { return nil }
            let link = Link(
                tag: tag,
                withPercent: mean(with),
                withoutPercent: mean(without),
                withNights: with.count,
                withoutNights: without.count
            )
            return abs(link.difference) >= minimumDifference ? link : nil
        }
        .sorted { abs($0.difference) > abs($1.difference) || (abs($0.difference) == abs($1.difference) && $0.tag < $1.tag) }
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

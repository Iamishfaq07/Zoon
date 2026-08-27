import CoreSpotlight
import Foundation
import os

/// Puts Zoon's *screens* in system search — and deliberately nothing else.
///
/// ## Why no sleep data
///
/// The obvious version of this feature indexes nights: "7h 32m, score 81,
/// Tuesday", so searching "Tuesday sleep" surfaces it. That version is not
/// built here, on purpose.
///
/// The Spotlight index lives outside the app's container. It is on-device, but
/// it is a *system* store: results surface on the Lock Screen, feed Siri
/// Suggestions, and persist independently of Zoon's own database. PRIVACY.md
/// says sleep, health, microphone, journal, and profile data are not sent to a
/// Zoon server — true, and unaffected by this — but copying nightly health
/// measurements into a system-wide index is still a real expansion of where
/// that data lives, and not one a sleep app should make quietly on the user's
/// behalf for the sake of a search result.
///
/// Screen names carry no health data. "Nap", "Wind Down", "Snore Check" reveal
/// which features exist, which is public information about the app rather than
/// anything about the person using it. That is the whole utility anyway: what
/// people want from Spotlight is a launcher — type "nap", land on the nap
/// timer — not a query engine over their own history, which the app's own
/// Insights tab already answers better.
///
/// If indexing nights is ever wanted, it should be an explicit opt-in with its
/// own Settings toggle and its own line in PRIVACY.md, not a side effect of
/// this.
enum SpotlightIndexer {

    private static let domain = "zoon.destinations"
    private static let identifierPrefix = "zoon.destination."
    private static let logger = Logger(subsystem: "com.zoon.sleep", category: "Spotlight")

    /// Title, subtitle, and the words someone would actually type.
    ///
    /// Keywords matter more than the title here: nobody searches "Soundscape",
    /// they search "white noise" or "rain".
    private struct Entry {
        let title: String
        let subtitle: String
        let keywords: [String]
    }

    private static func entry(for destination: DeepLink.Destination) -> Entry {
        switch destination {
        case .soundscapes:
            Entry(
                title: "Sleep Sounds",
                subtitle: "Brown noise, rain, ocean, fan",
                keywords: ["white noise", "brown noise", "pink noise", "rain", "ocean", "fan", "sounds", "sleep sounds"]
            )
        case .nap:
            Entry(
                title: "Nap",
                subtitle: "Start a timed nap",
                keywords: ["nap", "power nap", "timer", "rest"]
            )
        case .sleepDetail:
            Entry(
                title: "Last Night",
                subtitle: "Your sleep stages and score",
                keywords: ["last night", "hypnogram", "sleep stages", "rem", "deep sleep", "score"]
            )
        case .breathing:
            Entry(
                title: "Wind Down",
                subtitle: "Guided breathing before bed",
                keywords: ["breathing", "wind down", "4-7-8", "relax", "calm", "meditate"]
            )
        case .snoreCheck:
            Entry(
                title: "Snore Check",
                subtitle: "Listen for snoring overnight",
                keywords: ["snore", "snoring", "microphone", "listen"]
            )
        case .evidence:
            Entry(
                title: "What Zoon Knows",
                subtitle: "Every claim, ranked by how it was found",
                keywords: ["evidence", "claims", "proof", "tested", "experiment", "what changed", "discoveries", "believe"]
            )
        case .patterns:
            Entry(
                title: "Your Patterns",
                subtitle: "Where your best nights sit, and tomorrow's range",
                keywords: ["patterns", "sleep map", "forecast", "tomorrow", "range", "prediction", "longer nights"]
            )
        case .sensorTruth:
            Entry(
                title: "Where The Numbers Come From",
                subtitle: "Which are measured, and which are estimates",
                keywords: ["measured", "estimated", "accuracy", "sensor", "how it works", "provenance", "reliable", "stages"]
            )
        case .report:
            Entry(
                title: "Weekly Report",
                subtitle: "Your week in review",
                keywords: ["weekly report", "week", "summary", "review"]
            )
        case .settings:
            Entry(
                title: "Zoon Settings",
                subtitle: "Sleep goal, reminders, privacy",
                keywords: ["settings", "preferences", "sleep goal", "reminders", "privacy", "export"]
            )
        case .badges:
            Entry(
                title: "Badges",
                subtitle: "What you've earned so far",
                keywords: ["badges", "streak", "achievements", "awards"]
            )
        case .journal:
            Entry(
                title: "Journal",
                subtitle: "Log what might affect tonight",
                keywords: ["journal", "log", "habit", "caffeine", "alcohol", "tag"]
            )
        case .bodyClock:
            Entry(
                title: "Body Clock",
                subtitle: "Your preferred sleep window",
                keywords: ["body clock", "circadian", "rhythm", "chronotype", "window", "alignment"]
            )
        }
    }

    /// Indexes every destination. Safe to call on each launch — Spotlight
    /// treats a repeated identifier as an update, not a duplicate.
    static func indexDestinations() {
        let items = DeepLink.Destination.allCases.map { destination -> CSSearchableItem in
            let entry = entry(for: destination)
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = entry.title
            attributes.contentDescription = entry.subtitle
            attributes.keywords = entry.keywords

            return CSSearchableItem(
                uniqueIdentifier: identifierPrefix + destination.rawValue,
                domainIdentifier: domain,
                attributeSet: attributes
            )
        }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                logger.error("Indexing failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("Indexed \(items.count) destinations")
            }
        }
    }

    /// Removes everything Zoon put in the index.
    ///
    /// Called from Delete Everything. The index is outside the app container,
    /// so uninstalling clears it but "erase my data" would not — and PRIVACY.md
    /// promises that action leaves nothing behind.
    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { error in
            if let error {
                logger.error("Deindexing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Maps a tapped search result back to the destination it represents.
    ///
    /// Returns `nil` for anything unrecognised rather than guessing, so an
    /// identifier written by a future build can't route to the wrong screen.
    static func destination(forSearchableItemIdentifier identifier: String) -> DeepLink.Destination? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return DeepLink.Destination(rawValue: String(identifier.dropFirst(identifierPrefix.count)))
    }
}

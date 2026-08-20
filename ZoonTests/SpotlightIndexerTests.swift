import XCTest

/// The identifier round-trip decides which screen a Spotlight tap opens.
///
/// A mismatch here fails silently in the worst way: search results still
/// appear, tapping still launches the app, it just lands somewhere the user
/// didn't ask for. Nothing crashes and nothing logs, so it would survive
/// indefinitely.
final class SpotlightIndexerTests: XCTestCase {

    /// The load-bearing one. Every destination the app indexes must map back
    /// to itself, so adding a case can't quietly break routing for it.
    func testEveryDestinationRoundTrips() {
        for destination in DeepLink.Destination.allCases {
            let identifier = "zoon.destination." + destination.rawValue
            XCTAssertEqual(
                SpotlightIndexer.destination(forSearchableItemIdentifier: identifier),
                destination,
                "\(destination.rawValue) did not round-trip"
            )
        }
    }

    func testForeignIdentifierIsRejected() {
        // Another app's item, or a system identifier -- must not route.
        XCTAssertNil(SpotlightIndexer.destination(forSearchableItemIdentifier: "com.example.thing"))
        XCTAssertNil(SpotlightIndexer.destination(forSearchableItemIdentifier: ""))
    }

    func testUnknownZoonIdentifierIsRejectedRatherThanGuessed() {
        // Written by a future build that indexes a destination this one
        // doesn't have. Returning nil leaves the app on its default screen,
        // which is better than routing to an arbitrary one.
        XCTAssertNil(SpotlightIndexer.destination(forSearchableItemIdentifier: "zoon.destination.timeMachine"))
    }

    func testPrefixAloneIsNotADestination() {
        XCTAssertNil(SpotlightIndexer.destination(forSearchableItemIdentifier: "zoon.destination."))
    }
}

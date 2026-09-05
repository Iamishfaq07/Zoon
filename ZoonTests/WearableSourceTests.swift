import XCTest

/// Identifying a source is for wording only.
///
/// Nothing downstream branches on the brand -- capability is measured by
/// `SourceCoverage`. These tests pin that boundary as much as the matching
/// itself: an unrecognised watch must lose the display name and nothing else.
final class WearableSourceTests: XCTestCase {

    func testGarminIsRecognisedFromItsBundlePrefix() {
        XCTAssertEqual(
            WearableSource.identify(bundleIdentifier: "com.garmin.connect.mobile", name: "Garmin"),
            .garmin
        )
    }

    /// Prefixes, not exact identifiers: vendors ship more than one bundle,
    /// and an exact match would fall through to `unrecognised` on a rename.
    func testAVendorsOtherBundlesStillMatch() {
        XCTAssertEqual(
            WearableSource.identify(bundleIdentifier: "com.garmin.connect.mobile.watchkit", name: nil),
            .garmin
        )
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(
            WearableSource.identify(bundleIdentifier: "COM.GARMIN.CONNECT", name: nil),
            .garmin
        )
    }

    /// Rows written before Zoon recorded identifiers, and restored backups,
    /// have only a name.
    func testNameIsAFallbackWhenThereIsNoBundleIdentifier() {
        XCTAssertEqual(WearableSource.identify(bundleIdentifier: nil, name: "Garmin"), .garmin)
        XCTAssertEqual(WearableSource.identify(bundleIdentifier: "", name: "Fenix by Garmin"), .garmin)
    }

    /// An unknown source is a normal state, not an error: it keeps its name.
    func testAnUnknownSourceKeepsItsName() {
        let source = WearableSource.identify(
            bundleIdentifier: "com.example.sleeptracker",
            name: "Sleep Tracker Pro"
        )
        XCTAssertEqual(source, .unrecognised(name: "Sleep Tracker Pro"))
        XCTAssertEqual(source.displayName, "Sleep Tracker Pro")
        XCTAssertFalse(source.isRecognised)
    }

    /// "your Sleep Tracker Pro" reads like an endorsement Zoon has no
    /// business making, so unrecognised sources get a neutral phrase.
    func testUnrecognisedSourcesGetANeutralPossessive() {
        let source = WearableSource.identify(bundleIdentifier: "com.example.x", name: "Sleep Tracker Pro")
        XCTAssertEqual(source.possessivePhrase, "your device")
        XCTAssertEqual(WearableSource.garmin.possessivePhrase, "your Garmin")
    }

    /// Brand words only. "Health" and "Sleep" would match half the App Store.
    func testNameMatchingDoesNotFireOnGenericWords() {
        XCTAssertFalse(
            WearableSource.identify(bundleIdentifier: "com.example.app", name: "Sleep Health Tracker")
                .isRecognised
        )
    }
}

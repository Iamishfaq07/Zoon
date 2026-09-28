import XCTest

/// Delete Everything removes Zoon's share artefacts from the temporary
/// directory by name. The Month Recap image was once written as
/// `zoon-YYYY-MM.png`, which matched none of the prefixes, so a recap
/// image outlived the erase that promised to leave nothing behind.
final class TemporaryExportNameTests: XCTestCase {

    func testEveryShareArtefactIsRecognised() {
        for name in [
            "zoon-export-2026-09-28.json",
            "zoon-export-2026-09-28.csv",
            "Sleep_Report_2026-09-28.pdf",
            "zoon-week-2026-09-27.png",
            "zoon-month-2026-09.png",
            "zoon-last-night.png"
        ] {
            XCTAssertTrue(DataExporter.isTemporaryExport(name), name)
        }
    }

    func testTheOldMonthRecapNameIsStillErased() {
        XCTAssertTrue(DataExporter.isTemporaryExport("zoon-2026-09.png"))
    }

    func testFilesZoonDidNotWriteAreLeftAlone() {
        for name in [
            "zoon-2026-09.png.download",
            "zoon-notes.png",
            "photo.png",
            "com.apple.dyld"
        ] {
            XCTAssertFalse(DataExporter.isTemporaryExport(name), name)
        }
    }
}

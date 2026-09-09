import XCTest

final class ICloudArchiveSyncTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoon-icloud-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var container: ICloudArchiveSync.Container {
        .folder(folder)
    }

    func testANilUbiquityRootIsUnavailable() {
        XCTAssertEqual(
            ICloudArchiveSync.status(container: ICloudArchiveSync.Container { nil }),
            .unavailable
        )
    }

    func testAnEmptyContainerReportsEmpty() {
        XCTAssertEqual(ICloudArchiveSync.status(container: container), .empty)
    }

    func testAWrittenArchiveRoundTripsAndShowsItsSize() throws {
        let payload = Data("zoon-archive".utf8)
        try ICloudArchiveSync.write(payload, container: container)
        XCTAssertEqual(try ICloudArchiveSync.read(container: container), payload)

        guard case .present(_, let bytes) = ICloudArchiveSync.status(container: container) else {
            return XCTFail("expected a present backup")
        }
        XCTAssertEqual(bytes, payload.count)
    }

    func testReadingAnEmptyContainerFailsRatherThanInventingAFile() {
        XCTAssertThrowsError(try ICloudArchiveSync.read(container: container)) { error in
            XCTAssertEqual(error as? ICloudArchiveSync.Failure, .empty)
        }
    }
}

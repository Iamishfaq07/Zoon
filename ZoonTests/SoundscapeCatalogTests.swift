import XCTest

final class SoundscapeCatalogTests: XCTestCase {
    func testEveryGroupHasSoundsAndNoiseStaysGenerated() {
        for group in SoundscapeEngine.Sound.Group.allCases {
            XCTAssertFalse(
                SoundscapeEngine.Sound.allCases.filter { $0.group == group }.isEmpty,
                "\(group) should list at least one bed"
            )
        }
        for sound in SoundscapeEngine.Sound.allCases {
            switch sound.group {
            case .noise:
                XCTAssertNil(sound.fileName, "\(sound.rawValue) must stay generated")
            default:
                XCTAssertEqual(sound.fileName, sound.rawValue)
            }
        }
    }

    func testSiriNamesMatchEngineRawValues() {
        for siri in SoundscapeSound.allCases {
            XCTAssertNotNil(
                SoundscapeEngine.Sound(rawValue: siri.rawValue),
                "Siri case \(siri.rawValue) has no engine sound"
            )
        }
    }

    func testSiriDisplayRepresentationsCoverEveryCase() {
        let representations = SoundscapeSound.caseDisplayRepresentations
        for sound in SoundscapeSound.allCases {
            XCTAssertNotNil(
                representations[sound],
                "Siri case \(sound.rawValue) has no display representation"
            )
        }
        XCTAssertEqual(representations.count, SoundscapeSound.allCases.count)
    }

    func testRecordedBedsExistOnDisk() {
        let soundsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Zoon/Sounds", isDirectory: true)
        for sound in SoundscapeEngine.Sound.allCases {
            guard let name = sound.fileName else { continue }
            let file = soundsDir.appendingPathComponent("\(name).mp3", isDirectory: false)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: file.path),
                "\(name).mp3 is missing from Zoon/Sounds"
            )
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
            XCTAssertGreaterThan(size, 100_000, "\(name).mp3 looks empty (\(size) bytes)")
        }
    }

    func testGeneratedNoiseHasNoRecordedURL() {
        XCTAssertNil(SoundscapeEngine.Sound.brownNoise.recordedURL())
        XCTAssertNil(SoundscapeEngine.Sound.pinkNoise.recordedURL())
        XCTAssertNil(SoundscapeEngine.Sound.whiteNoise.recordedURL())
    }

    func testRecordedURLFindsFileAtBundleRoot() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoundscapeLookup-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try (["CFBundleIdentifier": "com.zoon.test.sounds", "CFBundlePackageType": "BNDL"] as NSDictionary)
            .write(to: dir.appendingPathComponent("Info.plist"))
        try Data(repeating: 0, count: 32).write(to: dir.appendingPathComponent("rain.mp3"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sounds", isDirectory: true), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32).write(
            to: dir.appendingPathComponent("Sounds", isDirectory: true).appendingPathComponent("ocean.mp3")
        )

        guard let bundle = Bundle(url: dir) else {
            XCTFail("could not open fixture bundle at \(dir.path)")
            return
        }
        XCTAssertEqual(
            SoundscapeEngine.Sound.rain.recordedURL(in: bundle)?.lastPathComponent,
            "rain.mp3",
            "yellow-group copy puts files at the bundle root"
        )
        XCTAssertEqual(
            SoundscapeEngine.Sound.ocean.recordedURL(in: bundle)?.lastPathComponent,
            "ocean.mp3",
            "folder-reference copy keeps Sounds/"
        )
        XCTAssertNil(SoundscapeEngine.Sound.forest.recordedURL(in: bundle))
    }
}

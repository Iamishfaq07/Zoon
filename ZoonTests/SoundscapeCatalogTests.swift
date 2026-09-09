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
}

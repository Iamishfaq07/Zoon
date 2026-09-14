import XCTest

/// The sky is background texture on four of its five screens, and texture does
/// not deserve a twelve-frame-a-second full-canvas redraw for the life of the
/// screen.
final class NightSkyPresenceTests: XCTestCase {

    /// Ambient instances redraw a quarter as often as immersive ones.
    func testAmbientRedrawsFarLessOften() {
        XCTAssertGreaterThan(
            NightSkyField.Presence.ambient.interval,
            NightSkyField.Presence.immersive.interval,
            "background texture must not tick as fast as the subject"
        )
        XCTAssertEqual(NightSkyField.Presence.immersive.interval, 1 / 12, accuracy: 0.0001)
        XCTAssertEqual(NightSkyField.Presence.ambient.interval, 1 / 3, accuracy: 0.0001)
    }

    /// A sky where every star pulses together reads as a flicker, not a sky —
    /// and costs the most.
    func testOnlySomeStarsTwinkleWhenAmbient() {
        XCTAssertEqual(NightSkyField.Presence.ambient.twinklingEvery, 4)
        XCTAssertEqual(NightSkyField.Presence.immersive.twinklingEvery, 1, "the subject may move freely")
    }

    /// Star geometry is deterministic, so the same screen draws the same sky
    /// each time rather than reshuffling on every state change.
    func testTheSkyIsStableAcrossRebuilds() {
        let first = NightSkyField.stars(count: 40, twinklingEvery: 4)
        let second = NightSkyField.stars(count: 40, twinklingEvery: 4)
        XCTAssertEqual(first.count, 40)
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.u, b.u)
            XCTAssertEqual(a.v, b.v)
            XCTAssertEqual(a.radius, b.radius)
            XCTAssertEqual(a.twinkles, b.twinkles)
        }
    }

    func testEveryStarSitsInsideTheCanvas() {
        for star in NightSkyField.stars(count: 56, twinklingEvery: 1) {
            XCTAssertTrue((0...1).contains(star.u))
            XCTAssertTrue((0...1).contains(star.v))
            XCTAssertGreaterThan(star.radius, 0)
        }
    }

    func testAmbientTwinkleShareIsRoughlyAQuarter() {
        let stars = NightSkyField.stars(count: 40, twinklingEvery: 4)
        let moving = stars.filter(\.twinkles).count
        XCTAssertEqual(moving, 10)
    }
}

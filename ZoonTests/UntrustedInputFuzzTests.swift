import XCTest

/// The app has no server, so its attack surface is every parser that reads
/// something from outside the process: an encrypted backup envelope, a
/// packet from the watch, a Spotlight identifier. Each is fed random and
/// mutated input here and must refuse it or handle it -- never trap.
///
/// (Plain backup JSON is fuzzed in `DataExporterTests`, beside its fixture.)
/// Seeded throughout, so any failure reproduces exactly.
final class UntrustedInputFuzzTests: XCTestCase {

    private var rng = SeededGenerator(seed: 0x5EC_F022)

    private func noise(_ count: ClosedRange<Int>) -> Data {
        Data((0..<Int.random(in: count, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })
    }

    // MARK: Encrypted backup envelope

    func testEncryptedEnvelopeRefusesNoiseAndForgedHeaders() throws {
        for _ in 0..<300 {
            XCTAssertThrowsError(try ArchiveCipher.open(noise(0...600), passphrase: "a long moon phrase"))
        }
        XCTAssertThrowsError(try ArchiveCipher.open(Data(), passphrase: ""))

        // Headers an attacker controls: salt length, iteration count, sealed
        // bytes of any length. Iteration counts inside the accepted range
        // are skipped here -- each costs a full key derivation -- and are
        // covered once below.
        for _ in 0..<300 {
            var rounds = UInt32.random(in: 0...UInt32.max, using: &rng)
            if (210_000...1_000_000).contains(rounds) { rounds = 5 }
            let envelope = ArchiveCipher.Envelope(
                salt: noise(0...40), rounds: rounds, sealed: noise(0...80)
            )
            let data = try JSONEncoder().encode(envelope)
            XCTAssertThrowsError(try ArchiveCipher.open(data, passphrase: "a long moon phrase"))
        }

        // A well-formed header over random ciphertext: derives, then fails
        // authentication rather than returning garbage.
        let forged = ArchiveCipher.Envelope(salt: noise(16...16), rounds: 210_000, sealed: noise(28...200))
        XCTAssertThrowsError(try ArchiveCipher.open(JSONEncoder().encode(forged), passphrase: "a long moon phrase"))
    }

    // MARK: Watch packets

    func testWatchPacketsDecodeOrFailWithoutTrapping() throws {
        let valid = try JSONEncoder().encode(WatchActionEnvelope(action: .behaviorTag(rawValue: "alcohol")))
        let name = "zoon.tests.fuzz.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let receipts = WatchActionReceiptStore(defaults: defaults)

        var inputs: [Data] = (0..<200).map { _ in noise(0...300) }
        for _ in 0..<300 {
            var bytes = [UInt8](valid)
            for _ in 0..<Int.random(in: 1...3, using: &rng) {
                bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 32...126, using: &rng)
            }
            inputs.append(Data(bytes))
        }
        // Dates and zones at the edges of what JSON can carry.
        for seconds in [-1e12, -1, 0, 1e12, 9e15] {
            let text = """
            {"id":"\(UUID().uuidString)","occurredAt":\(seconds),"timeZoneIdentifier":"Mars/Olympus",\
            "targetDate":\(-seconds),"action":{"midnightAwakening":{}}}
            """
            inputs.append(Data(text.utf8))
        }

        for data in inputs {
            guard let event = try? JSONDecoder().decode(WatchActionEnvelope.self, from: data) else { continue }
            _ = receipts.accepts(event)
            _ = receipts.hasRecorded(event)
            _ = event.behaviorNightDate
        }
    }

    // MARK: Spotlight identifiers

    func testSpotlightIdentifiersOnlyReachKnownDestinations() {
        let prefix = "zoon.destination."
        var identifiers = (0..<500).map { _ in String(decoding: noise(0...40), as: UTF8.self) }
        identifiers += (0..<200).map { _ in prefix + String(decoding: noise(0...20), as: UTF8.self) }
        identifiers += [prefix, prefix + "../settings", prefix + "nap\u{0}", "zoon.destination.NAP", prefix + " nap"]

        for identifier in identifiers {
            if let destination = SpotlightIndexer.destination(forSearchableItemIdentifier: identifier) {
                XCTAssertEqual(prefix + destination.rawValue, identifier, "only an exact known identifier routes")
            }
        }
        XCTAssertNotNil(SpotlightIndexer.destination(forSearchableItemIdentifier: prefix + "nap"))
    }
}

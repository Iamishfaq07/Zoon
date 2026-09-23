import XCTest

/// A backup carries everything it claims to, and a damaged one is refused
/// before anything is written.
@MainActor
final class ArchiveIntegrityTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func episode(id: String = "e1", start: Date? = nil, end: Date? = nil, asleep: Double = 25) -> DataExporter.Archive.EpisodeRecord {
        DataExporter.Archive.EpisodeRecord(
            id: id, nightKey: "night1",
            startDate: start ?? t0, endDate: end ?? t0.addingTimeInterval(1800),
            timezoneIdentifier: "Asia/Kolkata", episodeType: "nap",
            asleepMinutes: asleep, timeInBedMinutes: 30, sourceName: "Apple Watch"
        )
    }

    private func observation(
        behavior: String = "caffeineLate", quantity: Double? = 2, intensity: Double? = 0.5
    ) -> DataExporter.Archive.BehaviorObservationRecordExport {
        DataExporter.Archive.BehaviorObservationRecordExport(
            nightKey: "night1", behaviorIdentifier: behavior, state: "yes", source: "manual",
            observedAt: t0, quantity: quantity, unit: "cups",
            eventTime: t0.addingTimeInterval(-8 * 3600), intensity: intensity
        )
    }

    private func session(median: Double = 310, subjective: Int? = 4) -> AlertnessCheck.Session {
        AlertnessCheck.Session(
            id: UUID(), date: t0, medianMilliseconds: median, iqrMilliseconds: 40,
            lapses: 1, falseStarts: 0, trials: 20, minutesSinceWaking: 45,
            subjectiveAlertness: subjective
        )
    }

    private func archive(
        episodes: [DataExporter.Archive.EpisodeRecord]? = nil,
        observations: [DataExporter.Archive.BehaviorObservationRecordExport]? = nil,
        sessions: [AlertnessCheck.Session]? = nil,
        goal: Double = 480,
        snore: [SnoreStore.NightSummary] = [],
        naps: [NapStore.Nap] = []
    ) -> DataExporter.Archive {
        var archive = DataExporter.Archive(
            formatVersion: DataExporter.formatVersion, exportedAt: t0, goalMinutes: goal,
            nights: [], journal: [], naps: naps, preferences: nil, snoreSummaries: snore,
            wristTemperatures: [], episodes: episodes ?? [episode()], experiments: [],
            soundEvents: [], behaviorObservations: observations ?? [observation()]
        )
        archive.alertnessSessions = sessions ?? [session()]
        return archive
    }

    // MARK: - Lossless (Z05)

    /// Timed, quantified caffeine used to come back as "had caffeine" with
    /// the time and the amount gone.
    func testBehaviourDetailRoundTrips() throws {
        let decoded = try DataExporter.decode(DataExporter.jsonData(archive()))
        let restored = try XCTUnwrap(decoded.behaviorObservations?.first)
        XCTAssertEqual(restored.quantity, 2)
        XCTAssertEqual(restored.unit, "cups")
        XCTAssertEqual(restored.eventTime, t0.addingTimeInterval(-8 * 3600))
        XCTAssertEqual(restored.intensity, 0.5)
    }

    /// Alertness sessions were not in the archive at all.
    func testAlertnessSessionsRoundTrip() throws {
        let original = session(median: 287)
        let decoded = try DataExporter.decode(DataExporter.jsonData(archive(sessions: [original])))
        XCTAssertEqual(decoded.alertnessSessions, [original])
    }

    /// An archive from before format 6 has neither, and imports them as
    /// absent -- not as zero quantities or an empty-but-present history.
    func testAFormatFiveArchiveImportsTheNewFieldsAsAbsent() throws {
        let json = """
        {
          "formatVersion": 5, "exportedAt": "2023-11-14T22:13:20Z", "goalMinutes": 480,
          "nights": [], "journal": [], "naps": [],
          "behaviorObservations": [
            {"nightKey": "night1", "behaviorIdentifier": "alcohol", "state": "yes",
             "source": "manual", "observedAt": "2023-11-14T22:13:20Z"}
          ]
        }
        """
        let decoded = try DataExporter.decode(Data(json.utf8))
        let row = try XCTUnwrap(decoded.behaviorObservations?.first)
        XCTAssertNil(row.quantity)
        XCTAssertNil(row.eventTime)
        XCTAssertNil(decoded.alertnessSessions)
    }

    // MARK: - Validated before writes (Z06)

    func testAValidArchivePasses() {
        XCTAssertNil(DataExporter.validationFailure(archive()))
    }

    /// Reversed intervals reach `DateInterval(start:end:)` later, which traps.
    func testAReversedEpisodeIsRejected() {
        let reversed = episode(start: t0.addingTimeInterval(1800), end: t0)
        XCTAssertEqual(DataExporter.validationFailure(archive(episodes: [reversed])), "episode")
        XCTAssertThrowsError(try DataExporter.decode(DataExporter.jsonData(archive(episodes: [reversed]))))
    }

    func testDuplicateIdentitiesAreRejected() {
        XCTAssertEqual(
            DataExporter.validationFailure(archive(episodes: [episode(id: "x"), episode(id: "x")])),
            "duplicate episode"
        )
        XCTAssertEqual(
            DataExporter.validationFailure(archive(observations: [observation(), observation()])),
            "duplicate observation"
        )
    }

    /// Finite, but not a number of minutes anything could have slept.
    func testExtremeFiniteNumbersAreRejected() {
        XCTAssertEqual(DataExporter.validationFailure(archive(episodes: [episode(asleep: 1e300)])), "episode")
        XCTAssertEqual(DataExporter.validationFailure(archive(observations: [observation(quantity: 1e300)])), "observation")
        XCTAssertEqual(DataExporter.validationFailure(archive(observations: [observation(intensity: 7)])), "observation")
        XCTAssertEqual(DataExporter.validationFailure(archive(goal: 1e12)), "goal")
        XCTAssertEqual(DataExporter.validationFailure(archive(sessions: [session(median: 1e9)])), "alertness")
        XCTAssertEqual(DataExporter.validationFailure(archive(sessions: [session(subjective: 9)])), "alertness")
    }

    func testImpossibleSnoreIsRejected() {
        let snore = SnoreStore.NightSummary(date: t0, monitoredMinutes: 60, snoreMinutes: 600)
        XCTAssertEqual(DataExporter.validationFailure(archive(snore: [snore])), "snore")
    }

    func testAHugeArrayIsRejected() {
        let many = (0..<50_001).map { episode(id: "e\($0)") }
        XCTAssertEqual(DataExporter.validationFailure(archive(episodes: many)), "count")
    }

    func testAnOversizedFileIsRejectedBeforeDecoding() {
        let data = Data(count: DataExporter.maximumArchiveBytes + 1)
        XCTAssertThrowsError(try DataExporter.decode(data))
    }

    // MARK: - Alertness import

    func testAlertnessImportSkipsImplausibleSessionsAndKeepsExisting() throws {
        let defaults = UserDefaults(suiteName: "com.zoon.sleep.tests.alertness.\(UUID().uuidString)")!
        let store = AlertnessCheckStore(defaults: defaults)
        let good = session()
        let bad = session(median: 5)
        XCTAssertEqual(store.importSessions([good, bad]), 1)
        XCTAssertEqual(store.importSessions([good]), 0, "an existing session is not duplicated")
        XCTAssertEqual(AlertnessCheckStore(defaults: defaults).sessions.map(\.id), [good.id])
    }
}

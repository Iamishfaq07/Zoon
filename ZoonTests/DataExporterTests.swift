import XCTest

final class DataExporterTests: XCTestCase {

    private func makeArchive() -> DataExporter.Archive {
        DataExporter.Archive(
            formatVersion: DataExporter.formatVersion,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            goalMinutes: 480,
            nights: [],
            journal: [
                DataExporter.Archive.JournalRecord(
                    date: Date(timeIntervalSince1970: 1_700_000_000),
                    tags: ["alcohol"],
                    note: "Had a drink",
                    feeling: 3,
                    rested: 4,
                    energy: 3,
                    sleepiness: 2,
                    mood: 4,
                    nightKey: "night1"
                )
            ],
            naps: [],
            preferences: DataExporter.Archive.PreferencesRecord(
                age: 34,
                preferredEngine: "ruleBased",
                appearance: "dark",
                bedtimeRemindersEnabled: true,
                cycleTrackingEnabled: false,
                smartWakeEnabled: true,
                lifestyleInsightsEnabled: true,
                wakeAlarmEnabled: true,
                focusSilencesBedtimeNudges: true,
                preferredSleepSourceName: "Apple Watch",
                preferredSleepSourceBundleIdentifier: "com.apple.health.watch",
                obligationWeekdays: [2, 3, 4, 5, 6],
                isShiftWorkModeEnabled: false,
                trackedBehaviorTagIdentifiers: ["alcohol", "lateCaffeine"],
                activeExperimentTag: "alcohol",
                experimentStartDate: Date(timeIntervalSince1970: 1_699_000_000),
                experimentHypothesis: "Skipping it helps",
                experimentPrimaryMetric: "sleepPerformance",
                experimentDirection: "avoid"
            ),
            snoreSummaries: [],
            wristTemperatures: [],
            episodes: [
                DataExporter.Archive.EpisodeRecord(
                    id: "night1@1700000000",
                    nightKey: "night1",
                    startDate: Date(timeIntervalSince1970: 1_700_000_000),
                    endDate: Date(timeIntervalSince1970: 1_700_001_800),
                    timezoneIdentifier: "America/Los_Angeles",
                    episodeType: "nap",
                    asleepMinutes: 25,
                    timeInBedMinutes: 30,
                    sourceName: "Apple Watch"
                )
            ],
            experiments: [
                SleepExperimentStore.Outcome(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    tag: "alcohol",
                    hypothesis: "Skipping it helps",
                    startDate: Date(timeIntervalSince1970: 1_699_000_000),
                    endDate: Date(timeIntervalSince1970: 1_699_600_000),
                    metricLabel: "sleep sufficiency",
                    baselineMedian: 78,
                    trialMedian: 86,
                    baselineNightCount: 14,
                    trialNightCount: 9,
                    higherIsBetter: true,
                    trialKnownNightCount: 8
                )
            ],
            soundEvents: [
                SoundEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: Date(timeIntervalSince1970: 1_700_000_500), identifier: "snoring", confidence: 0.82)
            ],
            behaviorObservations: [
                DataExporter.Archive.BehaviorObservationRecordExport(
                    nightKey: "night1",
                    behaviorIdentifier: "alcohol",
                    state: "yes",
                    source: "manual",
                    observedAt: Date(timeIntervalSince1970: 1_700_000_100)
                ),
                DataExporter.Archive.BehaviorObservationRecordExport(
                    nightKey: "night1",
                    behaviorIdentifier: "caffeineLate",
                    state: "no",
                    source: "manual",
                    observedAt: Date(timeIntervalSince1970: 1_700_000_200)
                ),
            ]
        )
    }

    // MARK: - Round trip

    func testFormatVersionFourRoundTripsEveryNewField() throws {
        let original = makeArchive()
        let data = try DataExporter.jsonData(original)
        let decoded = try DataExporter.decode(data)

        XCTAssertEqual(decoded.formatVersion, 4)

        XCTAssertEqual(decoded.preferences?.wakeAlarmEnabled, true)
        XCTAssertEqual(decoded.preferences?.focusSilencesBedtimeNudges, true)
        XCTAssertEqual(decoded.preferences?.preferredSleepSourceName, "Apple Watch")
        XCTAssertEqual(decoded.preferences?.preferredSleepSourceBundleIdentifier, "com.apple.health.watch")
        XCTAssertEqual(decoded.preferences?.obligationWeekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(decoded.preferences?.isShiftWorkModeEnabled, false)
        XCTAssertEqual(decoded.preferences?.trackedBehaviorTagIdentifiers, ["alcohol", "lateCaffeine"])
        XCTAssertEqual(decoded.preferences?.activeExperimentTag, "alcohol")
        XCTAssertEqual(decoded.preferences?.experimentHypothesis, "Skipping it helps")
        XCTAssertEqual(decoded.preferences?.experimentPrimaryMetric, "sleepPerformance")
        XCTAssertEqual(decoded.preferences?.experimentDirection, "avoid")

        XCTAssertEqual(decoded.journal.count, 1)
        XCTAssertEqual(decoded.journal.first?.nightKey, "night1")

        XCTAssertEqual(decoded.episodes?.count, 1)
        XCTAssertEqual(decoded.episodes?.first?.id, "night1@1700000000")
        XCTAssertEqual(decoded.episodes?.first?.episodeType, "nap")
        XCTAssertEqual(decoded.episodes?.first?.asleepMinutes ?? -1, 25, accuracy: 0.001)

        XCTAssertEqual(decoded.experiments?.count, 1)
        XCTAssertEqual(decoded.experiments?.first?.tag, "alcohol")
        XCTAssertEqual(decoded.experiments?.first?.trialKnownNightCount, 8)

        XCTAssertEqual(decoded.soundEvents?.count, 1)
        XCTAssertEqual(decoded.soundEvents?.first?.identifier, "snoring")
    }

    // MARK: - Backward compatibility

    /// A format-2 export (built before episodes/experiments/soundEvents and
    /// the three new preference fields existed) has none of those keys in
    /// its JSON at all -- not `null`, genuinely absent. The whole point of
    /// making every new field Optional is that this still decodes cleanly
    /// instead of throwing `.unreadable`.
    func testFormatTwoArchiveWithoutNewFieldsStillDecodes() throws {
        let json = """
        {
            "formatVersion": 2,
            "exportedAt": "2023-11-14T22:13:20Z",
            "goalMinutes": 480,
            "nights": [],
            "journal": [],
            "naps": [],
            "preferences": {
                "age": 34,
                "preferredEngine": "ruleBased",
                "appearance": "dark",
                "bedtimeRemindersEnabled": true,
                "cycleTrackingEnabled": false,
                "smartWakeEnabled": true
            },
            "snoreSummaries": [],
            "wristTemperatures": []
        }
        """
        let decoded = try DataExporter.decode(Data(json.utf8))
        XCTAssertEqual(decoded.formatVersion, 2)
        XCTAssertNil(decoded.episodes)
        XCTAssertNil(decoded.experiments)
        XCTAssertNil(decoded.soundEvents)
        XCTAssertNil(decoded.preferences?.wakeAlarmEnabled)
        XCTAssertNil(decoded.preferences?.preferredSleepSourceName)
    }

    /// This is the gap the format-2 test above doesn't cover: an *old*
    /// export with a populated `nights` array, where each night JSON object
    /// itself predates fields like `isMock`, `stageSegments`,
    /// `secondaryAsleepMinutes`, and `timeZoneIdentifier`. Those are
    /// non-Optional properties with a declared default -- and Swift's
    /// synthesized `Decodable` does not apply a property's default value for
    /// a missing key, only `Optional`-typed properties get that leniency for
    /// free. Before `SleepNightFeatures` grew its own `init(from:)`, a real
    /// user's pre-format-3 backup with actual sleep history would fail this
    /// decode entirely and surface as "That file isn't a Zoon export, or
    /// it's damaged" -- a real backup misreported as corrupt.
    func testOldNightJSONMissingNewerFieldsStillDecodes() throws {
        let json = """
        {
            "formatVersion": 1,
            "exportedAt": "2023-01-01T00:00:00Z",
            "goalMinutes": 480,
            "nights": [
                {
                    "date": "2023-01-01T07:00:00Z",
                    "bedtime": "2023-01-01T00:00:00Z",
                    "wakeTime": "2023-01-01T07:00:00Z",
                    "timeInBedMinutes": 420,
                    "timeAsleepMinutes": 400,
                    "sleepEfficiencyPercent": 95.2,
                    "coreMinutes": 200,
                    "deepMinutes": 80,
                    "remMinutes": 90,
                    "unspecifiedAsleepMinutes": 30,
                    "awakeMinutes": 20,
                    "wakeCount": 3,
                    "sleepLatencyMinutes": 10,
                    "avgHeartRate": 58,
                    "minHeartRate": 50,
                    "avgHRV": 45,
                    "avgRespiratoryRate": 14,
                    "avgSpO2": 97,
                    "wristTempDeltaC": null,
                    "hrv7DayAvg": null,
                    "sleepDebtMinutes": null,
                    "lastWorkoutHoursBeforeBed": null,
                    "exerciseMinutesPreviousDay": null,
                    "sourceName": "Apple Watch"
                }
            ],
            "journal": [],
            "naps": [],
            "preferences": null,
            "snoreSummaries": [],
            "wristTemperatures": []
        }
        """
        let decoded = try DataExporter.decode(Data(json.utf8))
        XCTAssertEqual(decoded.nights.count, 1)
        let night = try XCTUnwrap(decoded.nights.first)
        XCTAssertEqual(night.timeAsleepMinutes, 400, accuracy: 0.001)
        XCTAssertFalse(night.isMock)
        XCTAssertFalse(night.timeInBedIsEstimated)
        XCTAssertEqual(night.secondaryAsleepMinutes, 0, accuracy: 0.001)
        XCTAssertTrue(night.stageSegments.isEmpty)
        XCTAssertEqual(night.timeZoneIdentifier, TimeZone.current.identifier)
    }

    // MARK: - Behaviour answers

    /// The reason the format went to 4. A backup that silently omitted these
    /// would restore every behaviour to unknown while still reporting a
    /// complete import, which is worse than refusing to import at all.
    func testBehaviourAnswersRoundTripWithTheirStateAndSource() throws {
        let decoded = try DataExporter.decode(try DataExporter.jsonData(makeArchive()))
        let observations = try XCTUnwrap(decoded.behaviorObservations)

        XCTAssertEqual(observations.count, 2)
        let alcohol = try XCTUnwrap(observations.first { $0.behaviorIdentifier == "alcohol" })
        XCTAssertEqual(alcohol.state, "yes")
        XCTAssertEqual(alcohol.nightKey, "night1")
        XCTAssertEqual(alcohol.source, "manual")

        // The negative is the load-bearing one: it is the only kind of
        // evidence that can form a control arm, and it is exactly what the
        // old tag-list format had no way to express.
        let caffeine = try XCTUnwrap(observations.first { $0.behaviorIdentifier == "caffeineLate" })
        XCTAssertEqual(caffeine.state, "no")
    }

    /// A version 3 archive predates the field entirely. It must still import,
    /// with no answers rather than answers reconstructed from its positive
    /// tags -- the legacy-tag path in `exposureState` already covers those,
    /// and synthesising rows here would claim the archive held answers it
    /// never did.
    func testAVersionThreeArchiveStillImportsWithNoAnswers() throws {
        let json = """
        {
          "formatVersion": 3,
          "exportedAt": "2023-11-14T22:13:20Z",
          "goalMinutes": 480,
          "nights": [],
          "journal": [],
          "naps": []
        }
        """
        let decoded = try DataExporter.decode(Data(json.utf8))

        XCTAssertEqual(decoded.formatVersion, 3)
        XCTAssertNil(decoded.behaviorObservations)
    }

    /// A file from a *future* Zoon version must still be rejected with a
    /// clear message rather than silently importing a partial, possibly
    /// misinterpreted subset of a format this version doesn't understand.
    func testNewerFormatVersionIsRejected() {
        var archive = makeArchive()
        archive = DataExporter.Archive(
            formatVersion: DataExporter.formatVersion + 1,
            exportedAt: archive.exportedAt, goalMinutes: archive.goalMinutes,
            nights: archive.nights, journal: archive.journal, naps: archive.naps,
            preferences: archive.preferences, snoreSummaries: archive.snoreSummaries,
            wristTemperatures: archive.wristTemperatures, episodes: archive.episodes,
            experiments: archive.experiments, soundEvents: archive.soundEvents,
            behaviorObservations: archive.behaviorObservations
        )
        guard let data = try? DataExporter.jsonData(archive) else {
            return XCTFail("expected the archive to encode")
        }
        XCTAssertThrowsError(try DataExporter.decode(data)) { error in
            guard case DataExporter.ImportError.unsupportedVersion(let version) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(version, DataExporter.formatVersion + 1)
        }
    }
}

import HealthKit
import SwiftData
import XCTest

/// Audit §10: why a value is missing is kept, and a store that could not be
/// read is never treated as an empty one.
@MainActor
final class FetchStateTests: XCTestCase {

    // MARK: - MetricFetchState

    func testEveryIssueMapsToAStateAndBack() {
        for issue in FetchIssue.allCases where issue != .storeUnreadable {
            XCTAssertEqual(MetricFetchState<Int>(issue: issue).issue, issue)
        }
        XCTAssertEqual(MetricFetchState<Int>(issue: .storeUnreadable).issue, .queryFailed)
    }

    func testOnlyAValueHasAValue() {
        XCTAssertEqual(MetricFetchState.value(42).value, 42)
        XCTAssertNil(MetricFetchState.value(42).issue)
        for issue in FetchIssue.allCases {
            XCTAssertNil(MetricFetchState<Int>(issue: issue).value, "\(issue) must read as unknown, never zero")
        }
    }

    func testNothingRecordedIsNotAProblem() {
        XCTAssertFalse(FetchIssue.notRecorded.isProblem)
        for issue in FetchIssue.allCases where issue != .notRecorded {
            XCTAssertTrue(issue.isProblem)
        }
    }

    /// The copy a person sees never carries a raw error and never diagnoses.
    func testExplanationsArePlainAndDistinct() {
        let texts = FetchIssue.allCases.map(\.explanation)
        XCTAssertEqual(Set(texts).count, texts.count)
        for text in texts {
            XCTAssertFalse(text.contains("Error Domain"), text)
            XCTAssertFalse(text.contains("HKError"), text)
            XCTAssertFalse(DiagnosticLanguageGuard.rejects(text), text)
        }
    }

    // MARK: - FetchDiagnosticLog

    private func diagnostic(_ source: String, _ issue: FetchIssue, _ secondsAgo: TimeInterval = 0,
                            subsystem: FetchDiagnostic.Subsystem = .healthKit) -> FetchDiagnostic {
        FetchDiagnostic(subsystem: subsystem, operation: "test", issue: issue, sourceType: source,
                        timestamp: Date(timeIntervalSince1970: 1_000_000 - secondsAgo))
    }

    func testALaterSuccessClearsTheProblem() {
        var log = FetchDiagnosticLog()
        log.record(diagnostic("stepCount", .accessDenied))
        XCTAssertEqual(log.issue(for: "stepCount"), .accessDenied)
        log.clear(subsystem: .healthKit, sourceType: "stepCount")
        XCTAssertNil(log.issue(for: "stepCount"))
        XCTAssertEqual(log.totalRecorded, 1, "cleared problems still count toward the session total")
    }

    func testANotRecordedResultClearsRatherThanAdds() {
        var log = FetchDiagnosticLog()
        log.record(diagnostic("heartRate", .temporarilyUnavailable))
        log.record(diagnostic("heartRate", .notRecorded))
        XCTAssertTrue(log.problems.isEmpty)
    }

    func testOneRowPerSourceLatestWinsNewestFirst() {
        var log = FetchDiagnosticLog()
        log.record(diagnostic("stepCount", .temporarilyUnavailable, 30))
        log.record(diagnostic("workout", .queryFailed, 20))
        log.record(diagnostic("stepCount", .accessDenied, 10))
        XCTAssertEqual(log.problems.map(\.sourceType), ["stepCount", "workout"])
        XCTAssertEqual(log.issue(for: "stepCount"), .accessDenied)
    }

    func testTheSameNameInTwoSubsystemsIsTwoRows() {
        var log = FetchDiagnosticLog()
        log.record(diagnostic("x", .queryFailed, subsystem: .healthKit))
        log.record(diagnostic("x", .storeUnreadable, subsystem: .store))
        XCTAssertEqual(log.problems.count, 2)
    }

    func testTheLogIsBounded() {
        var log = FetchDiagnosticLog()
        for i in 0..<(FetchDiagnosticLog.capacity + 20) {
            log.record(diagnostic("source-\(i)", .queryFailed, TimeInterval(-i)))
        }
        XCTAssertEqual(log.problems.count, FetchDiagnosticLog.capacity)
        XCTAssertEqual(log.problems.first?.sourceType, "source-\(FetchDiagnosticLog.capacity + 19)")
    }

    func testSourcesHaveNamesPeopleUse() {
        XCTAssertEqual(diagnostic("stepCount", .accessDenied).displayName, "Steps")
        XCTAssertEqual(diagnostic("SleepNightRecord", .storeUnreadable).displayName, "Saved nights")
        XCTAssertEqual(diagnostic("somethingNew", .queryFailed).displayName, "somethingNew")
    }

    // MARK: - HealthKit classification

    func testHealthKitErrorsAreClassifiedByMeaning() {
        XCTAssertEqual(HealthFetchClassifier.issue(for: HKError(.errorAuthorizationDenied)), .accessDenied)
        XCTAssertEqual(HealthFetchClassifier.issue(for: HKError(.errorAuthorizationNotDetermined)), .accessDenied)
        XCTAssertEqual(HealthFetchClassifier.issue(for: HKError(.errorHealthDataUnavailable)), .unsupported)
        XCTAssertEqual(HealthFetchClassifier.issue(for: HKError(.errorHealthDataRestricted)), .unsupported)
        XCTAssertEqual(HealthFetchClassifier.issue(for: HKError(.errorDatabaseInaccessible)), .temporarilyUnavailable)
        XCTAssertEqual(HealthFetchClassifier.issue(for: HKError(.errorNoData)), .notRecorded)
        XCTAssertEqual(HealthFetchClassifier.issue(for: HKError(.errorInvalidArgument)), .queryFailed)
        XCTAssertEqual(HealthFetchClassifier.issue(for: CancellationError()), .temporarilyUnavailable)
        XCTAssertEqual(HealthFetchClassifier.issue(for: HealthKitError.unavailable), .unsupported)
        XCTAssertEqual(HealthFetchClassifier.issue(for: NSError(domain: "Other", code: 1)), .queryFailed)
    }

    func testTheLogCodeCarriesNoMessage() {
        let error = NSError(domain: "com.apple.healthkit", code: 6, userInfo: [NSLocalizedDescriptionKey: "Private detail"])
        let code = HealthFetchClassifier.logCode(for: error)
        XCTAssertEqual(code, "com.apple.healthkit#6")
        XCTAssertFalse(code.contains("Private"))
    }

    // MARK: - HealthRead

    private struct Denied: Error {}

    func testAFailedReadIsUnknownAndRecorded() async {
        let diagnostics = FetchDiagnostics()
        let state: MetricFetchState<Double?> = await HealthRead.fetch("activity.steps", source: "stepCount", diagnostics: diagnostics) {
            throw HKError(.errorAuthorizationDenied)
        }
        XCTAssertNil(state.value)
        XCTAssertEqual(state.issue, .accessDenied)
        XCTAssertEqual(diagnostics.log.issue(for: "stepCount"), .accessDenied)
    }

    func testASuccessfulReadClearsAnEarlierFailure() async {
        let diagnostics = FetchDiagnostics()
        _ = await HealthRead.fetch("activity.steps", source: "stepCount", diagnostics: diagnostics) { () -> Double in
            throw HKError(.errorDatabaseInaccessible)
        }
        XCTAssertEqual(diagnostics.log.issue(for: "stepCount"), .temporarilyUnavailable)
        let state = await HealthRead.fetch("activity.steps", source: "stepCount", diagnostics: diagnostics) { 1234.0 }
        XCTAssertEqual(state.value, 1234)
        XCTAssertNil(diagnostics.log.issue(for: "stepCount"))
    }

    // MARK: - Store lookups

    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SleepNightRecord.self, SleepEpisodeRecord.self, EvidenceRevisionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    func testALookupSaysAbsentWhenThereIsNothing() throws {
        let context = try makeContext()
        let lookup = context.lookupFirst(FetchDescriptor<SleepEpisodeRecord>(), operation: "test")
        guard case .absent = lookup else { return XCTFail("expected .absent, got \(lookup)") }
        XCTAssertEqual(context.readCount(FetchDescriptor<SleepEpisodeRecord>(), operation: "test"), 0)
    }

    func testALookupFindsTheRow() throws {
        let context = try makeContext()
        context.insert(SleepEpisodeRecord(
            id: "e1", nightKey: "n1", startDate: .now, endDate: .now, timezoneIdentifier: "UTC",
            episodeType: .nap, asleepMinutes: 20, timeInBedMinutes: 25, sourceName: nil
        ))
        try context.save()
        XCTAssertEqual(context.lookupFirst(FetchDescriptor<SleepEpisodeRecord>(), operation: "test").value?.id, "e1")
    }

    /// A failed read is counted, so a backup gathered across it is refused.
    func testAFailedStoreReadIsCountedAndShown() {
        let before = StoreRead.failureCount
        StoreRead.failed(operation: "test", type: "SleepNightRecord", error: NSError(domain: "test", code: 1))
        XCTAssertEqual(StoreRead.failureCount, before + 1)
        XCTAssertEqual(FetchDiagnostics.shared.log.issue(for: "SleepNightRecord"), .storeUnreadable)
        StoreRead.succeeded(type: "SleepNightRecord")
        XCTAssertNil(FetchDiagnostics.shared.log.issue(for: "SleepNightRecord"))
    }

    func testTheBackupRefusalSaysNothingWasChanged() {
        let message = IncompleteHistoryReadError().errorDescription ?? ""
        XCTAssertTrue(message.contains("no backup was made"), message)
        XCTAssertTrue(message.contains("Nothing was changed"), message)
    }
}

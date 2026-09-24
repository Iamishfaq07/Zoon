import Foundation
import Observation

/// Audit §10: a read that failed is not a read that found nothing.
///
/// HealthKit calls used to be `try? await ...` and SwiftData reads
/// `(try? context.fetch(...)) ?? []`, so access turned off, a locked device,
/// an unsupported type and a failing store all looked exactly like "there was
/// no sample". The value a caller gets is unchanged -- `nil` still means
/// unknown -- but why it is unknown is now kept, locally, and shown.

/// Why a read produced no value.
enum FetchIssue: String, Codable, Sendable, CaseIterable {
    /// The query ran and there was nothing to find.
    case notRecorded
    /// Read access is off or was never granted. HealthKit does not reveal
    /// which, by design.
    case accessDenied
    /// The data exists but could not be read right now (device locked, the
    /// read was cancelled). Worth trying again later.
    case temporarilyUnavailable
    /// This device cannot provide the type at all.
    case unsupported
    /// The query failed for another reason.
    case queryFailed
    /// Zoon's own saved history could not be read.
    case storeUnreadable

    /// Plain-language copy. Never contains the raw error.
    var explanation: String {
        switch self {
        case .notRecorded: "Nothing recorded."
        case .accessDenied: "Zoon can't read this. Check Health access in Settings > Health > Data Access & Devices > Zoon."
        case .temporarilyUnavailable: "Couldn't read this just now, usually because the phone was locked. Zoon will try again."
        case .unsupported: "This device doesn't provide this data."
        case .queryFailed: "Reading this failed. Zoon will try again on the next refresh."
        case .storeUnreadable: "Zoon couldn't read its saved history. Nothing was deleted; it will try again."
        }
    }

    var shortLabel: String {
        switch self {
        case .notRecorded: "Not recorded"
        case .accessDenied: "No access"
        case .temporarilyUnavailable: "Temporarily unavailable"
        case .unsupported: "Not supported"
        case .queryFailed: "Read failed"
        case .storeUnreadable: "History unreadable"
        }
    }

    /// Whether this is a problem to show, rather than an honest absence.
    var isProblem: Bool { self != .notRecorded }
}

/// The result of reading one metric.
enum MetricFetchState<Value> {
    case value(Value)
    case notRecorded
    case notAvailableOnDevice
    case authorizationUnknownOrDenied
    case temporarilyUnavailable
    case queryFailed

    init(issue: FetchIssue) {
        switch issue {
        case .notRecorded: self = .notRecorded
        case .accessDenied: self = .authorizationUnknownOrDenied
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        case .unsupported: self = .notAvailableOnDevice
        case .queryFailed, .storeUnreadable: self = .queryFailed
        }
    }

    /// The value, or `nil` for every kind of unknown.
    var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }

    var issue: FetchIssue? {
        switch self {
        case .value: nil
        case .notRecorded: .notRecorded
        case .notAvailableOnDevice: .unsupported
        case .authorizationUnknownOrDenied: .accessDenied
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .queryFailed: .queryFailed
        }
    }
}

/// One failed read, as kept on device. No raw error text: the category, what
/// was being read and when.
struct FetchDiagnostic: Codable, Equatable, Sendable, Identifiable {
    enum Subsystem: String, Codable, Sendable {
        case healthKit, store
    }

    var id: String { "\(subsystem.rawValue).\(sourceType)" }
    let subsystem: Subsystem
    /// What the app was doing ("activity.steps", "history.upsertLookup").
    let operation: String
    let issue: FetchIssue
    /// The data being read ("stepCount", "SleepNightRecord").
    let sourceType: String
    let timestamp: Date

    /// What a person would call the data.
    var displayName: String {
        Self.displayNames[sourceType] ?? sourceType
    }

    static let displayNames: [String: String] = [
        "stepCount": "Steps",
        "heartRate": "Heart rate",
        "activeEnergyBurned": "Active energy",
        "appleExerciseTime": "Exercise minutes",
        "workout": "Workouts",
        "menstrualFlow": "Cycle tracking",
        "sleepAnalysis": "Sleep sources",
        "numberOfAlcoholicBeverages": "Alcohol",
        "dietaryCaffeine": "Caffeine",
        "SleepNightRecord": "Saved nights",
        "SleepEpisodeRecord": "Saved naps and split sleep",
        "EvidenceRevisionRecord": "Evidence history",
        "JournalEntry": "Journal",
        "BehaviorObservationRecord": "Behaviour answers"
    ]
}

/// The latest problem per data source. A later successful read of the same
/// source clears it, so what is listed is what is wrong now.
struct FetchDiagnosticLog: Equatable, Sendable {
    static let capacity = 50

    private(set) var current: [FetchDiagnostic] = []
    /// Every problem recorded since launch, including ones since cleared.
    private(set) var totalRecorded = 0

    mutating func record(_ diagnostic: FetchDiagnostic) {
        guard diagnostic.issue.isProblem else {
            clear(subsystem: diagnostic.subsystem, sourceType: diagnostic.sourceType)
            return
        }
        totalRecorded += 1
        current.removeAll { $0.id == diagnostic.id }
        current.append(diagnostic)
        if current.count > Self.capacity { current.removeFirst(current.count - Self.capacity) }
    }

    mutating func clear(subsystem: FetchDiagnostic.Subsystem, sourceType: String) {
        current.removeAll { $0.subsystem == subsystem && $0.sourceType == sourceType }
    }

    /// Newest first.
    var problems: [FetchDiagnostic] { current.sorted { $0.timestamp > $1.timestamp } }

    func issue(for sourceType: String) -> FetchIssue? {
        current.last { $0.sourceType == sourceType }?.issue
    }
}

/// The app's diagnostics, in memory only. Nothing leaves the device.
@MainActor
@Observable
final class FetchDiagnostics {
    static let shared = FetchDiagnostics()

    private(set) var log = FetchDiagnosticLog()

    func record(_ subsystem: FetchDiagnostic.Subsystem, operation: String, sourceType: String, issue: FetchIssue, at date: Date = .now) {
        log.record(FetchDiagnostic(subsystem: subsystem, operation: operation, issue: issue, sourceType: sourceType, timestamp: date))
    }

    func succeeded(_ subsystem: FetchDiagnostic.Subsystem, sourceType: String) {
        log.clear(subsystem: subsystem, sourceType: sourceType)
    }

    func reset() {
        log = FetchDiagnosticLog()
    }
}

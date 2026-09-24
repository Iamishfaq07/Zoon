import Foundation
import HealthKit
import os

/// Maps a HealthKit read error to a `FetchIssue`, so the reason a value is
/// missing survives without the raw error being shown to anyone.
///
/// Only long-standing `HKError.Code` cases are matched; anything else is
/// `.queryFailed`.
enum HealthFetchClassifier {
    static func issue(for error: Error) -> FetchIssue {
        if error is CancellationError { return .temporarilyUnavailable }
        if let healthKitError = error as? HealthKitError {
            switch healthKitError {
            case .unavailable: return .unsupported
            }
        }
        guard let hkError = error as? HKError else { return .queryFailed }
        switch hkError.code {
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
            return .accessDenied
        case .errorHealthDataUnavailable, .errorHealthDataRestricted:
            return .unsupported
        case .errorDatabaseInaccessible, .errorUserCanceled:
            return .temporarilyUnavailable
        case .errorNoData:
            return .notRecorded
        default:
            return .queryFailed
        }
    }

    /// A safe code for the device log: domain and number, never the message.
    static func logCode(for error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain)#\(ns.code)"
    }
}

/// A HealthKit read with its outcome typed (audit §10). A failure is
/// recorded in `FetchDiagnostics` under `source`, by category only; a later
/// success clears it. Nothing is sent anywhere.
@MainActor
enum HealthRead {
    private static let logger = Logger(subsystem: "com.zoon.sleep", category: "HealthRead")

    static func fetch<T>(
        _ operation: String,
        source: String,
        _ read: () async throws -> T
    ) async -> MetricFetchState<T> {
        await fetch(operation, source: source, diagnostics: FetchDiagnostics.shared, read)
    }

    static func fetch<T>(
        _ operation: String,
        source: String,
        diagnostics: FetchDiagnostics,
        _ read: () async throws -> T
    ) async -> MetricFetchState<T> {
        do {
            let value = try await read()
            diagnostics.succeeded(.healthKit, sourceType: source)
            return .value(value)
        } catch {
            let issue = HealthFetchClassifier.issue(for: error)
            diagnostics.record(.healthKit, operation: operation, sourceType: source, issue: issue)
            logger.error("HealthKit read \(operation, privacy: .public) failed: \(HealthFetchClassifier.logCode(for: error), privacy: .public)")
            return MetricFetchState(issue: issue)
        }
    }

    /// `fetch` for callers that only need the value: `nil` is still
    /// "unknown", as `try?` gave, but the reason is no longer thrown away.
    static func value<T>(_ operation: String, source: String, _ read: () async throws -> T) async -> T? {
        await fetch(operation, source: source, read).value
    }
}

enum HealthKitError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Health data isn't available on this device. Zoon needs an iPhone with the Health app."
        }
    }
}

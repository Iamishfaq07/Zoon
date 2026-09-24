import Foundation
import SwiftData
import os

/// Audit §10 for SwiftData: an unreadable store is not an empty one.
///
/// `(try? context.fetch(...)) ?? []` made a failing store look empty, and
/// several writers look a row up before inserting it -- so a failed lookup
/// became a duplicate night, journal day or evidence revision, and a backup
/// taken at that moment was silently missing history. Reads now say whether
/// they could read; writers that cannot check for an existing row do not
/// insert; nothing is ever deleted because a read failed.
enum StoreLookup<Value> {
    case found(Value)
    case absent
    case unreadable

    var value: Value? {
        if case .found(let value) = self { return value }
        return nil
    }
}

@MainActor
enum StoreRead {
    private static let logger = Logger(subsystem: "com.zoon.sleep", category: "StoreRead")

    /// Failed reads since launch. A backup compares this before and after
    /// gathering history and refuses to write a partial archive.
    private(set) static var failureCount = 0

    static func failed(operation: String, type: String, error: Error) {
        failureCount += 1
        let ns = error as NSError
        logger.error("Store read \(operation, privacy: .public) on \(type, privacy: .public) failed: \(ns.domain, privacy: .public)#\(ns.code)")
        FetchDiagnostics.shared.record(.store, operation: operation, sourceType: type, issue: .storeUnreadable)
    }

    static func succeeded(type: String) {
        FetchDiagnostics.shared.succeeded(.store, sourceType: type)
    }
}

/// Thrown when a backup could not read everything it was meant to include.
struct IncompleteHistoryReadError: LocalizedError {
    var errorDescription: String? {
        "Zoon couldn't read all of its saved history, so no backup was made. Nothing was changed. Try again in a moment."
    }
}

@MainActor
extension ModelContext {

    /// Every matching row, or `nil` when the store could not be read.
    func readAll<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, operation: String) -> [T]? {
        do {
            let rows = try fetch(descriptor)
            StoreRead.succeeded(type: String(describing: T.self))
            return rows
        } catch {
            StoreRead.failed(operation: operation, type: String(describing: T.self), error: error)
            return nil
        }
    }

    /// The first matching row, distinguishing "none" from "couldn't look".
    func lookupFirst<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, operation: String) -> StoreLookup<T> {
        guard let rows = readAll(descriptor, operation: operation) else { return .unreadable }
        return rows.first.map { .found($0) } ?? .absent
    }

    func readCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, operation: String) -> Int? {
        do {
            let count = try fetchCount(descriptor)
            StoreRead.succeeded(type: String(describing: T.self))
            return count
        } catch {
            StoreRead.failed(operation: operation, type: String(describing: T.self), error: error)
            return nil
        }
    }
}

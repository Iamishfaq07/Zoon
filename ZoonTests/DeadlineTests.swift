import XCTest

/// A timeout that returns when it says it will, even when the operation
/// never does.
final class DeadlineTests: XCTestCase {

    /// The HealthKit case: a completion handler that never fires and ignores
    /// cancellation. A task-group timeout waited on it forever.
    func testAnOperationThatNeverFinishesStillTimesOut() async {
        let started = Date()
        do {
            _ = try await Deadline.race(seconds: 0.3) { () async throws -> Int in
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
                    // Deliberately never resumed.
                }
                return 1
            }
            XCTFail("expected the deadline to win")
        } catch {
            XCTAssertEqual(error as? Deadline.Expired, Deadline.Expired())
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "returned long after the deadline")
    }

    func testAFastOperationWins() async throws {
        let value = try await Deadline.race(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    /// A late answer after the deadline is discarded, not delivered twice.
    func testALateCompletionIsIgnored() async {
        do {
            _ = try await Deadline.race(seconds: 0.1) { () async throws -> Int in
                try? await Task.sleep(nanoseconds: 400_000_000)
                return 7
            }
            XCTFail("expected the deadline to win")
        } catch {
            XCTAssertTrue(error is Deadline.Expired)
        }
        // Outlive the operation; a double resume would trap here.
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    func testAnOperationErrorIsPassedThrough() async {
        struct Boom: Error {}
        do {
            _ = try await Deadline.race(seconds: 5) { () async throws -> Int in throw Boom() }
            XCTFail("expected the error")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }
}

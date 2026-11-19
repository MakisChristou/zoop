import XCTest
@testable import ZoopData
@MainActor final class RefreshTests: XCTestCase {
    func testExhaustionAndEarlyCompletion() async throws {
        var calls = 0
        let exhausted = try await RefreshPoller.wait(attempts: 3, delay: .zero) { calls += 1; return false }
        XCTAssertFalse(exhausted); XCTAssertEqual(calls,3)
        calls = 0
        let done = try await RefreshPoller.wait(attempts: 30, delay: .zero) { calls += 1; return calls == 2 }
        XCTAssertTrue(done); XCTAssertEqual(calls,2)
    }
    func testCancellationInterruptsWait() async {
        let task = Task { try await RefreshPoller.wait(attempts: 100, delay: .seconds(10)) { false } }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled wait must stop") } catch { XCTAssertTrue(error is CancellationError) }
    }
}

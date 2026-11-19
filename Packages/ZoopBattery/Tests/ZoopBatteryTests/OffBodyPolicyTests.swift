import XCTest
@testable import ZoopBattery

final class OffBodyPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testRemovalWaitsTenMinutesAndDuplicateDoesNotPostpone() {
        var policy = OffBodyPolicy()
        XCTAssertTrue(policy.receive(worn: false, at: now, now: now, live: true))
        XCTAssertEqual(policy.deadline, now.addingTimeInterval(600))
        XCTAssertTrue(policy.receive(worn: false, at: now.addingTimeInterval(20), now: now.addingTimeInterval(20), live: true))
        XCTAssertEqual(policy.deadline, now.addingTimeInterval(600))
        XCTAssertTrue(policy.receive(worn: true, at: now.addingTimeInterval(100), now: now.addingTimeInterval(100), live: true))
        XCTAssertNil(policy.deadline)
    }
    func testHistoricalFutureAndOutOfOrderEventsCannotStartAnAlert() {
        var policy = OffBodyPolicy()
        XCTAssertFalse(policy.receive(worn: false, at: now, now: now, live: false))
        XCTAssertFalse(policy.receive(worn: false, at: now.addingTimeInterval(-61), now: now, live: true))
        XCTAssertFalse(policy.receive(worn: false, at: now.addingTimeInterval(60), now: now, live: true))
        policy.receive(worn: true, at: now, now: now, live: true)
        XCTAssertFalse(policy.receive(worn: false, at: now.addingTimeInterval(-1), now: now, live: true))
        XCTAssertNil(policy.deadline)
    }
    func testDisconnectCancelsAndFreshRemovalStartsNewEpisode() {
        var policy = OffBodyPolicy(); policy.receive(worn: false, at: now, now: now, live: true)
        policy.invalidate(); XCTAssertNil(policy.deadline)
        let later = now.addingTimeInterval(900)
        policy.receive(worn: false, at: later, now: later, live: true)
        XCTAssertEqual(policy.deadline, later.addingTimeInterval(600))
    }
}

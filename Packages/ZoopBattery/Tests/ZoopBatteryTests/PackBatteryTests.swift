import Foundation
import XCTest
@testable import ZoopBattery

final class PackBatteryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let packID: [UInt8] = [1, 2, 3, 4, 5, 6]

    func testCachedReplyDoesNotNotifyOrBlockLiveEvent() {
        var pack = PackBatteryState()
        var policy = BatteryAlertPolicy()
        XCTAssertTrue(pack.receive(percent: 3, identifier: packID, at: start, now: start, live: false, cached: true))
        XCTAssertEqual(pack.percent, 3)
        XCTAssertFalse(pack.isLive(at: start))
        XCTAssertNil(policy.evaluate(pack.battery, now: start, live: pack.isLive(at: start)))
        let eventDate = start.addingTimeInterval(-1)
        XCTAssertTrue(pack.receive(percent: 19, identifier: packID, at: eventDate, now: start, live: true))
        XCTAssertEqual(pack.percent, 19)
        XCTAssertTrue(pack.isLive(at: start))
        XCTAssertEqual(policy.evaluate(pack.battery, now: start, live: pack.isLive(at: start)), .low(20))
        XCTAssertFalse(pack.receive(percent: 3, identifier: packID, at: start, now: start, live: false, cached: true))
    }

    func testHistoryNeverCreatesLivePresenceOrAlerts() {
        var pack = PackBatteryState()
        pack.receive(percent: 5, identifier: packID, at: start, now: start, live: false)
        XCTAssertEqual(pack.percent, 5)
        XCTAssertNil(pack.present)
        XCTAssertFalse(pack.isLive(at: start))
        XCTAssertFalse(pack.receivePresence(true, at: start, now: start, live: false))
        var policy = BatteryAlertPolicy()
        XCTAssertNil(policy.evaluate(pack.battery, now: start, live: pack.isLive(at: start)))
    }

    func testRemovalDisconnectAndExpiryKeepLastReadingWithoutLiveStatus() throws {
        var pack = PackBatteryState()
        pack.receive(percent: 56, identifier: packID, at: start, now: start, live: true)
        let removed = start.addingTimeInterval(10)
        XCTAssertTrue(pack.receivePresence(false, at: removed, now: removed, live: true))
        XCTAssertFalse(pack.isLive(at: removed))
        XCTAssertEqual(pack.percent, 56)
        pack.receive(percent: 55, identifier: packID, at: start.addingTimeInterval(5), now: removed, live: true)
        XCTAssertEqual(pack.present, false)
        XCTAssertFalse(pack.isLive(at: removed))
        let next = removed.addingTimeInterval(10)
        pack.receivePresence(true, at: next, now: next, live: true)
        pack.receive(percent: 54, identifier: packID, at: next, now: next, live: true)
        XCTAssertTrue(pack.isLive(at: next))
        XCTAssertFalse(pack.isLive(at: next.addingTimeInterval(901)))
        pack.disconnect(at: next.addingTimeInterval(1))
        XCTAssertFalse(pack.isLive(at: next))
        let restored = try JSONDecoder().decode(PackBatteryState.self, from: JSONEncoder().encode(pack))
        XCTAssertEqual(restored.percent, 54)
        XCTAssertFalse(restored.isLive(at: next))
    }

    func testFlowAndNotificationsTrackPackSeparately() {
        var pack = PackBatteryState()
        var policy = BatteryAlertPolicy()
        pack.receive(percent: 23, identifier: packID, at: start, now: start, live: true)
        XCTAssertNil(pack.flow)
        XCTAssertNil(policy.evaluate(pack.battery, now: start, live: true))
        let low = start.addingTimeInterval(600)
        pack.receive(percent: 19, identifier: packID, at: low, now: low, live: true)
        XCTAssertEqual(pack.flow, .discharging)
        XCTAssertEqual(policy.evaluate(pack.battery, now: low, live: pack.isLive(at: low)), .low(20))
        XCTAssertNil(policy.evaluate(pack.battery, now: low, live: true))
        let rising = low.addingTimeInterval(600)
        pack.receive(percent: 20, identifier: packID, at: rising, now: rising, live: true)
        XCTAssertEqual(pack.flow, .discharging, "One rebound must not imply charging")
        let risingAgain = rising.addingTimeInterval(600)
        pack.receive(percent: 22, identifier: packID, at: risingAgain, now: risingAgain, live: true)
        XCTAssertEqual(pack.flow, .charging)
        XCTAssertNil(policy.evaluate(pack.battery, now: risingAgain, live: true))
        let full = risingAgain.addingTimeInterval(600)
        pack.receive(percent: 100, identifier: packID, at: full, now: full, live: true)
        XCTAssertEqual(policy.evaluate(pack.battery, now: full, live: true), .charged)
        XCTAssertNil(policy.evaluate(pack.battery, now: full, live: true))
    }

    func testInvalidReadingsAndPackSwap() {
        var pack = PackBatteryState()
        XCTAssertFalse(pack.receive(percent: 101, identifier: packID, at: start, now: start, live: true))
        XCTAssertFalse(pack.receive(percent: .nan, identifier: packID, at: start, now: start, live: true))
        XCTAssertFalse(pack.receive(percent: 50, identifier: packID, at: start.addingTimeInterval(61), now: start, live: true))
        pack.receive(percent: 5, identifier: packID, at: start, now: start, live: true)
        let later = start.addingTimeInterval(20)
        XCTAssertTrue(pack.receive(percent: 90, identifier: [7, 8, 9, 10, 11, 12], at: later, now: later, live: true))
        XCTAssertNil(pack.flow)
        XCTAssertEqual(pack.percent, 90)
        XCTAssertFalse(pack.receive(percent: 4, identifier: packID, at: later.addingTimeInterval(-1), now: later, live: false))
        XCTAssertEqual(pack.percent, 90)
    }

    func testFractionalTimestampsPreserveFullChargeAndRejectLateOlderReading() {
        var pack = PackBatteryState()
        var policy = BatteryAlertPolicy()
        let first = start.addingTimeInterval(0.2)
        let full = start.addingTimeInterval(0.8)
        pack.receive(percent: 99.9, identifier: packID, at: first, now: first, live: true)
        XCTAssertNil(policy.evaluate(pack.battery, now: first, live: true))
        pack.receive(percent: 100, identifier: packID, at: full, now: full, live: true)
        XCTAssertEqual(policy.evaluate(pack.battery, now: full, live: true), .charged)
        XCTAssertFalse(pack.receive(percent: 99.9, identifier: packID, at: first, now: full, live: true))
        XCTAssertEqual(pack.percent, 100)
        XCTAssertNil(policy.evaluate(pack.battery, now: full, live: true))
    }
}

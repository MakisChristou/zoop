import Foundation
import XCTest
@testable import ZoopBattery

final class BatteryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReplayAndInvalidReadingsCannotReplaceNewerData() {
        var state = BatteryState()
        XCTAssertTrue(state.receive(percent: 18, at: now, now: now))
        XCTAssertFalse(state.receive(percent: 90, at: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(state.receive(percent: 20, at: now, now: now))
        XCTAssertFalse(state.receive(percent: 100.1, at: now.addingTimeInterval(1), now: now))
        XCTAssertFalse(state.receive(percent: .nan, at: now.addingTimeInterval(1), now: now))
        XCTAssertFalse(state.receive(percent: 4, at: now.addingTimeInterval(3600), now: now))
        XCTAssertEqual(state.percent, 18)
        state.receive(charging: false, at: now, now: now)
        state.receive(charging: true, at: now.addingTimeInterval(-10), now: now)
        XCTAssertEqual(state.charging, false)
    }

    func testThresholdsEscalateWithoutRepeatingOrSpammingOnFirstLowReading() {
        var state = BatteryState()
        var policy = BatteryAlertPolicy()
        for (offset, percent, expected) in [(0, 19.0, 20), (10, 18.0, 0), (20, 9.0, 10), (30, 4.0, 5), (40, 3.0, 0)] {
            let time = now.addingTimeInterval(Double(offset))
            state.receive(percent: percent, at: time, now: time)
            XCTAssertEqual(policy.evaluate(state, now: time, live: true), expected == 0 ? nil : .low(expected))
        }
        var firstLow = BatteryAlertPolicy()
        XCTAssertEqual(firstLow.evaluate(state, now: now.addingTimeInterval(40), live: true), .low(5))
        XCTAssertEqual(firstLow.warned, [5, 10, 20])
    }

    func testHistoryAndStaleDataNeverNotify() {
        var state = BatteryState()
        var policy = BatteryAlertPolicy()
        state.receive(percent: 3, at: now, now: now)
        XCTAssertNil(policy.evaluate(state, now: now, live: false))
        XCTAssertNil(policy.evaluate(state, now: now.addingTimeInterval(901), live: true))
        XCTAssertEqual(policy.warned, [])
    }

    func testChargingSuppressesLowAndRearmsWithHysteresis() {
        var state = BatteryState()
        var policy = BatteryAlertPolicy()
        state.receive(percent: 5, at: now, now: now)
        XCTAssertEqual(policy.evaluate(state, now: now, live: true), .low(5))
        let t1 = now.addingTimeInterval(10)
        state.receive(charging: true, at: t1, now: t1)
        state.receive(percent: 6, at: t1, now: t1)
        XCTAssertNil(policy.evaluate(state, now: t1, live: true))
        XCTAssertEqual(policy.warned, [5, 10, 20])
        let t2 = now.addingTimeInterval(20)
        state.receive(percent: 26, at: t2, now: t2)
        XCTAssertNil(policy.evaluate(state, now: t2, live: true))
        XCTAssertEqual(policy.warned, [])
        let t3 = now.addingTimeInterval(30)
        state.receive(charging: false, at: t3, now: t3)
        state.receive(percent: 19, at: t3, now: t3)
        XCTAssertEqual(policy.evaluate(state, now: t3, live: true), .low(20))
    }

    func testFullChargeMustReach100AndSurvivesRestart() throws {
        var state = BatteryState()
        var policy = BatteryAlertPolicy()
        state.receive(charging: true, at: now, now: now)
        state.receive(percent: 99.9, at: now, now: now)
        XCTAssertNil(policy.evaluate(state, now: now, live: true))
        let t1 = now.addingTimeInterval(30)
        state.receive(percent: 100, at: t1, now: t1)
        XCTAssertEqual(policy.evaluate(state, now: t1, live: true), .charged)
        var restored = try JSONDecoder().decode(BatteryAlertPolicy.self, from: JSONEncoder().encode(policy))
        state = try JSONDecoder().decode(BatteryState.self, from: JSONEncoder().encode(state))
        let t2 = now.addingTimeInterval(60)
        state.receive(percent: 100, at: t2, now: t2)
        XCTAssertNil(restored.evaluate(state, now: t2, live: true))
        var firstLaunch = BatteryAlertPolicy()
        XCTAssertNil(firstLaunch.evaluate(state, now: t2, live: true))
    }

    func testReconnectCannotReviveAnOldChargingSession() {
        var state = BatteryState()
        state.receive(charging: true, at: now, now: now)
        let reconnect = now.addingTimeInterval(120)
        state.invalidateCharging(at: reconnect)
        XCTAssertNil(state.charging)
        XCTAssertFalse(state.receive(charging: true, at: now, now: reconnect))
        let next = reconnect.addingTimeInterval(1)
        XCTAssertTrue(state.receive(charging: true, at: next, now: next))
        XCTAssertEqual(state.charging, true)
    }

    func testChargingWhileDisconnectedRearmsLowAlerts() {
        var state = BatteryState()
        var policy = BatteryAlertPolicy()
        state.receive(percent: 4, at: now, now: now)
        XCTAssertEqual(policy.evaluate(state, now: now, live: true), .low(5))
        let reconnect = now.addingTimeInterval(7200)
        state.receive(percent: 80, at: reconnect, now: reconnect)
        XCTAssertNil(policy.evaluate(state, now: reconnect, live: true))
        let later = reconnect.addingTimeInterval(7200)
        state.receive(percent: 20, at: later, now: later)
        XCTAssertEqual(policy.evaluate(state, now: later, live: true), .low(20))
    }

    func testFirstReadingNearFullArmsCompletionWithoutDuplicateAt99Percent() {
        var state = BatteryState()
        var policy = BatteryAlertPolicy()
        for (offset, percent, expected) in [(0, 99.0, false), (30, 100.0, true), (60, 99.0, false), (90, 100.0, false)] {
            let time = now.addingTimeInterval(Double(offset))
            state.receive(percent: percent, at: time, now: time)
            XCTAssertEqual(policy.evaluate(state, now: time, live: true), expected ? .charged : nil)
        }
    }
}

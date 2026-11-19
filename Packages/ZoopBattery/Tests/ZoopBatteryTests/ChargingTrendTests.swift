import Foundation
import XCTest
@testable import ZoopBattery

final class ChargingTrendTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testMidChargeLaunchRecoversFromSustainedLiveRise() {
        var state = BatteryState()
        for (index, percent) in [40.0, 40.6, 41.2].enumerated() {
            let at = start.addingTimeInterval(Double(index * 30))
            state.receive(percent: percent, at: at, now: at, live: true)
            XCTAssertEqual(state.chargingStatus(at: at), index == 2 ? true : nil)
        }
        XCTAssertEqual(state.chargingEvidence, .risingLevel)
        XCTAssertNil(state.chargingStatus(at: start.addingTimeInterval(241)))
    }

    func testRoundingDifferencesBetweenQueriesAndEventsCannotLookLikeCharging() {
        var state = BatteryState()
        for index in 0..<10 {
            let at = start.addingTimeInterval(Double(index * 15))
            let isQuery = index.isMultiple(of: 2)
            let percent = isQuery ? 40 : 40.9 - Double(index) / 100
            state.receive(percent: percent, at: at, now: at, live: true, source: isQuery ? .query : .event)
            XCTAssertNotEqual(state.chargingStatus(at: at), true)
        }
    }

    func testHistoryAndWidelySeparatedReadingsCannotInferCharging() {
        var history = BatteryState()
        var gaps = BatteryState()
        for index in 0..<4 {
            let at = start.addingTimeInterval(Double(index * 200))
            history.receive(percent: Double(40 + index), at: at, now: at, live: false)
            gaps.receive(percent: Double(40 + index), at: at, now: at, live: true)
        }
        XCTAssertNil(history.charging)
        XCTAssertNil(gaps.charging)
    }

    func testFallingLevelEndsInferenceButDoesNotOverrideConfirmedCharging() {
        var state = BatteryState()
        for index in 0..<3 {
            let at = start.addingTimeInterval(Double(index * 30))
            state.receive(percent: Double(40 + index), at: at, now: at, live: true)
        }
        let fall = start.addingTimeInterval(90)
        state.receive(percent: 41.7, at: fall, now: fall, live: true)
        XCTAssertEqual(state.chargingStatus(at: fall), false)
        let confirmed = fall.addingTimeInterval(1)
        state.receive(charging: true, at: confirmed, now: confirmed)
        let later = fall.addingTimeInterval(30)
        state.receive(percent: 41.5, at: later, now: later, live: true)
        XCTAssertEqual(state.chargingStatus(at: later), true)
        XCTAssertEqual(state.chargingEvidence, .event)
    }

    func testRecentTrendSurvivesRestartAndExplicitOffStopsIt() throws {
        var state = BatteryState()
        for index in 0..<3 {
            let at = start.addingTimeInterval(Double(index * 30))
            state.receive(percent: Double(40 + index), at: at, now: at, live: true)
        }
        state = try JSONDecoder().decode(BatteryState.self, from: JSONEncoder().encode(state))
        state.invalidateCharging(at: start.addingTimeInterval(70))
        XCTAssertNil(state.charging)
        let next = start.addingTimeInterval(90)
        state.receive(percent: 43, at: next, now: next, live: true)
        XCTAssertEqual(state.chargingStatus(at: next), true)
        let off = next.addingTimeInterval(1)
        state.receive(charging: false, at: off, now: off)
        XCTAssertEqual(state.chargingStatus(at: off), false)
    }

    func testLegacySavedStateStillDecodesAndInferenceSuppressesLowAlerts() throws {
        let legacy = Data("{\"percent\":8,\"levelAt\":0}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(BatteryState.self, from: legacy).percent, 8)
        var state = BatteryState()
        var policy = BatteryAlertPolicy()
        for index in 0..<3 {
            let at = start.addingTimeInterval(Double(index * 30))
            state.receive(percent: Double(8 + index), at: at, now: at, live: true)
        }
        XCTAssertEqual(state.charging, true)
        XCTAssertNil(policy.evaluate(state, now: start.addingTimeInterval(60), live: true))
    }
}

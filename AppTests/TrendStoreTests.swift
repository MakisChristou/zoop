import XCTest
import ZoopData
@testable import Zoop

private actor TrendTestServer {
    var calls = 0
    var delay = false
    var failing = false
    func fail() { failing = true }
    func setDelay() { delay = true }
    func nights(_ device: String) async throws -> [ZoopAPI.Night] {
        calls += 1
        if failing { throw URLError(.notConnectedToInternet) }
        if delay && calls == 1 { try await Task.sleep(for: .milliseconds(80)) }
        return [TrendStoreTests.night(day: device == "old" ? "2026-10-26" : "2026-11-01")]
    }
    func count() -> Int { calls }
}

@MainActor final class TrendStoreTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z")!
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; c.firstWeekday = 2; return c }

    func testEveryRangeKeepsRecordedValuesAndExistingRollingSemantics() {
        let nights = ["2025-10-01", "2025-11-03", "2026-08-01", "2026-08-05", "2026-10-01", "2026-10-15", "2026-10-26", "2026-10-27", "2026-11-01"].map { Self.night(day: $0) }
        let days = [Self.day("2026-10-15", steps: 1200), Self.day("2026-10-27", steps: nil), Self.day("2026-11-01", steps: 2300)]
        let snapshot = TrendSnapshot(nights: nights, days: days, now: now, calendar: calendar)
        XCTAssertEqual(TrendRange.allCases.map { snapshot.series(.sleep, range: $0).points.count }, [3, 1, 5, 7])
        XCTAssertEqual(snapshot.series(.steps, range: .week).points.map(\.value), [2300])
        XCTAssertEqual(snapshot.series(.steps, range: .month).points.map(\.value), [2300])
        let expected: [TrendMetric: Double] = [.sleep: 7.5, .restingHr: 52, .hrv: 66, .breathing: 14.5, .skinTemp: 32.2, .efficiency: 90]
        for range in TrendRange.allCases {
            for (metric, value) in expected {
                let series = snapshot.series(metric, range: range)
                XCTAssertTrue(series.points.allSatisfy { $0.value == value })
                XCTAssertEqual(series.average ?? 0, value, accuracy: 0.00001)
                XCTAssertEqual(series.rolling.count, series.points.count)
                XCTAssertTrue(series.rolling.allSatisfy { abs($0.value - value) < 0.00001 })
            }
        }
    }

    func testBrowsingPreparedRangesDoesNotReloadOrLoseWiderHistory() async throws {
        let server = TrendTestServer()
        let store = TrendStore(loadNights: { try await server.nights($0) }, loadDays: { _ in [Self.day("2026-10-15", steps: 1200), Self.day("2026-11-01", steps: 2300)] })
        await store.reload(device: "new", connection: "one", now: now, calendar: calendar)
        for _ in 0..<100 {
            XCTAssertEqual(store.snapshot.series(.steps, range: .week).points.count, 1)
            XCTAssertEqual(store.snapshot.series(.steps, range: .month).points.count, 1)
        }
        let calls = await server.count()
        XCTAssertEqual(calls, 1)
        XCTAssertNil(store.error)
    }

    func testSupersededRefreshCannotReplaceNewConnection() async throws {
        let server = TrendTestServer(); await server.setDelay()
        let store = TrendStore(loadNights: { try await server.nights($0) }, loadDays: { _ in [] })
        let old = Task { await store.reload(device: "old", connection: "old", now: now, calendar: calendar) }
        try await Task.sleep(for: .milliseconds(10))
        await store.reload(device: "new", connection: "new", now: now, calendar: calendar)
        await old.value
        XCTAssertEqual(store.snapshot.nights.map(\.nightOf), ["2026-11-01"])
    }

    func testCancelledRefreshAndEmptyDeviceCannotPublishOldHistory() async throws {
        let server = TrendTestServer(); await server.setDelay()
        let store = TrendStore(loadNights: { try await server.nights($0) }, loadDays: { _ in [] })
        let load = Task { await store.reload(device: "old", connection: "one", now: now, calendar: calendar) }
        try await Task.sleep(for: .milliseconds(10)); load.cancel(); await load.value
        XCTAssertTrue(store.snapshot.nights.isEmpty)
        await store.reload(device: "new", connection: "one", now: now, calendar: calendar)
        XCTAssertFalse(store.snapshot.nights.isEmpty)
        await store.reload(device: "", connection: "one", now: now, calendar: calendar)
        XCTAssertTrue(store.snapshot.nights.isEmpty)
        XCTAssertNotNil(store.error)
    }

    func testFailedRefreshRetainsUsableSnapshotForEveryRange() async {
        let server = TrendTestServer()
        let store = TrendStore(loadNights: { try await server.nights($0) }, loadDays: { _ in [Self.day("2026-11-01", steps: 2300)] })
        await store.reload(device: "new", connection: "one", now: now, calendar: calendar)
        await server.fail()
        await store.reload(device: "new", connection: "one", now: now, calendar: calendar)
        XCTAssertNotNil(store.error)
        for range in TrendRange.allCases {
            XCTAssertEqual(store.snapshot.series(.sleep, range: range).points.count, 1)
            XCTAssertEqual(store.snapshot.series(.steps, range: range).points.map(\.value), [2300])
        }
    }

    func testCredentialChangeDuringRequestRejectsItsResult() async {
        let store = TrendStore(loadNights: { _ in [Self.night(day: "2026-11-01")] }, loadDays: { _ in [] })
        await store.reload(device: "new", connection: "old", now: now, calendar: calendar, isCurrent: { false })
        XCTAssertTrue(store.snapshot.nights.isEmpty)
        XCTAssertNil(store.error)
    }

    nonisolated static func night(day: String) -> ZoopAPI.Night {
        let wake = DayKey.date(day, timeZone: TimeZone(secondsFromGMT: 0)!)!.addingTimeInterval(9 * 3600)
        let start = wake.addingTimeInterval(-8 * 3600)
        return .init(nightOf: day, algoVersion: 2, startTs: start, endTs: wake, stages: [], metrics: .init(window: .init(onset: start, offset: wake, timeInBedS: 28800, asleepS: 27000, wasoS: 1800, efficiency: 0.9, coverageS: 28800, disturbances: 1), physiology: .init(restingHr: 52, hrvRmssdMs: 66, hrvWindows: 40, respiratoryRate: 14.5, skinTempC: 32.2, spo2Pct: nil, spo2Windows: 0), stages: nil, naps: []))
    }
    nonisolated private static func day(_ key: String, steps: Int?) -> ZoopAPI.Day {
        .init(day: key, steps: steps, stepsWalking: steps, walkingS: nil, hrMin: nil, hrAvg: nil, hrMax: nil, skinTempAvg: nil, asleepS: nil, samples: 100, load: nil, trimp: nil, kcal: nil, zonesMin: nil)
    }
}

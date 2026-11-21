import XCTest
@testable import Zoop

@MainActor final class RecoveryHistoryStoreTests: XCTestCase {
    private func snapshot(_ timezone: String = "Pacific/Auckland") -> RecoveryHistoryStore.Snapshot {
        .init(timezone: timezone, rows: [], now: Date())
    }
    func testKeepsServerTimezoneAndScopesHistory() async {
        let store = RecoveryHistoryStore { _ in self.snapshot() }
        await store.reload(device: "strap", connection: "owner")
        XCTAssertEqual(store.value(device: "strap", connection: "owner")?.calendar.timeZone.identifier, "Pacific/Auckland")
        XCTAssertNil(store.value(device: "other", connection: "owner"))
        XCTAssertNil(store.value(device: "strap", connection: "other"))
    }
    func testSupersededResponseCannotCrossAccounts() async {
        let store = RecoveryHistoryStore { device in
            if device == "old" { try? await Task.sleep(for: .milliseconds(60)) }
            return self.snapshot(device == "old" ? "UTC" : "Asia/Nicosia")
        }
        let old = Task { await store.reload(device: "old", connection: "a") }
        await Task.yield()
        await store.reload(device: "new", connection: "b")
        await old.value
        XCTAssertEqual(store.value(device: "new", connection: "b")?.timezone, "Asia/Nicosia")
    }
    func testFailedRefreshPreservesSameAccountOnly() async {
        var fail = false
        let store = RecoveryHistoryStore { _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return self.snapshot()
        }
        await store.reload(device: "strap", connection: "a")
        fail = true
        await store.reload(device: "strap", connection: "a")
        XCTAssertNotNil(store.value(device: "strap", connection: "a"))
        XCTAssertTrue(store.failed)
        await store.reload(device: "strap", connection: "b")
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(store.failed)
        XCTAssertFalse(store.loading)
    }
    func testCancellationDoesNotPublish() async {
        let store = RecoveryHistoryStore { _ in
            try? await Task.sleep(for: .milliseconds(30))
            return self.snapshot()
        }
        let task = Task { await store.reload(device: "strap", connection: "a") }
        await Task.yield(); task.cancel(); await task.value
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.loading)
    }
    func testPreparedDaysKeepGapsAndRespectDaylightSaving() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "recovery-insights", withExtension: "json"))
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let recovery = try XCTUnwrap(decoder.decode(MorningInsights.self, from: Data(contentsOf: url)).recovery)
        let rows = ["2026-03-29", "invalid", "2026-03-27"].map {
            RecoveryDay(day: $0, recovery: recovery, hrvMs: 72, restingHr: 54)
        }
        let snapshot = RecoveryHistoryStore.Snapshot(timezone: "Europe/Berlin", rows: rows, now: Date())
        XCTAssertEqual(snapshot.points.map(\.row.day), ["2026-03-27", "2026-03-29"])
        XCTAssertEqual(snapshot.points[0].end.timeIntervalSince(snapshot.points[0].start), 24 * 3600 * 0.72, accuracy: 0.01)
        XCTAssertEqual(snapshot.points[1].end.timeIntervalSince(snapshot.points[1].start), 23 * 3600 * 0.72, accuracy: 0.01)
        XCTAssertNil(snapshot.byDay["2026-03-28"])
        XCTAssertEqual(snapshot.byDay["2026-03-29"]?.recovery.displayedScore, recovery.displayedScore)
    }
    func testBackendProjectionPreservesNullAndZero() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "recovery-insights", withExtension: "json"))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var reading = object["recovery"] as! [String: Any]
        reading["score"] = 0; reading["band"] = "low"
        let data = try JSONSerialization.data(withJSONObject: ["day":"2026-11-21", "recovery": reading, "hrv_ms": NSNull(), "resting_hr": 47])
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let day = try decoder.decode(RecoveryDay.self, from: data)
        XCTAssertEqual(day.recovery.displayedScore, 0)
        XCTAssertEqual(day.recovery.band, "low")
        XCTAssertNil(day.hrvMs)
        XCTAssertEqual(day.restingHr, 47)
    }
}

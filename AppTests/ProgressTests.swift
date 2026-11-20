import XCTest
@testable import Zoop

@MainActor final class ProgressTests: XCTestCase {
    nonisolated static func summary(_ zone: String = "UTC") -> ZoopAPI.ProgressSummary {
        .init(timezone: zone, current: .init(start: "2026-10-08", end: "2026-11-04"), previous: .init(start: "2026-09-10", end: "2026-10-07"), metrics: [.init(key: "steps", current: 7800, previous: 6600, change: 1200, currentCount: 28, previousCount: 28, requiredCount: 21, weeks: [nil, 6000, 7000, 6800, 8000, 7600, 7800, 7800])])
    }
    func testFormattingKeepsUnitsAndNoSignedZero() {
        XCTAssertEqual(ProgressFormat.value(26640, key: "sleep"), "7h 24m")
        XCTAssertEqual(ProgressFormat.delta(1080, key: "sleep"), "+18 min")
        XCTAssertEqual(ProgressFormat.delta(-0.2, key: "steps"), "0")
        XCTAssertEqual(ProgressFormat.value(nil, key: "sleep"), "—")
        XCTAssertEqual(ProgressFormat.value(.nan, key: "steps"), "—")
        XCTAssertEqual(ProgressFormat.delta(-20, key: "wake_variation"), "−20 min")
    }
    func testDateLabelsUseTheResponseZoneAcrossDST() {
        let period = ZoopAPI.ProgressSummary.Period(start: "2026-10-25", end: "2026-11-01")
        let label = period.label(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        XCTAssertTrue(label.contains("25")); XCTAssertTrue(label.contains("1")); XCTAssertTrue(label.contains("2026"))
    }
    func testDeviceAndCredentialSwitchDiscardsOldResponse() async throws {
        let store = ProgressStore { device in
            if device == "old" { try await Task.sleep(for: .milliseconds(80)) }
            return Self.summary(device)
        }
        let old = Task { await store.reload(device: "old", connection: "one") }
        try await Task.sleep(for: .milliseconds(10))
        await store.reload(device: "new", connection: "two")
        await old.value
        XCTAssertEqual(store.summary?.timezone, "new")
        await store.reload(device: "new", connection: "three", isCurrent: { false })
        XCTAssertNil(store.summary)
    }
    func testCancellationDoesNotPublishAndClearsLoading() async {
        let store = ProgressStore { _ in try await Task.sleep(for: .milliseconds(80)); return Self.summary() }
        let task = Task { await store.reload(device: "test", connection: "one") }; task.cancel(); await task.value
        XCTAssertNil(store.summary); XCTAssertFalse(store.loading)
        await store.reload(device: "", connection: "one")
        XCTAssertNotNil(store.error); XCTAssertFalse(store.loading)
    }
    func testDecodeRetainsMissingWeeksAndUnavailableComparison() throws {
        let data = Data(#"{"key":"steps","current":7000,"previous":null,"change":null,"current_count":5,"previous_count":0,"required_count":21,"weeks":[null,null,null,null,null,null,null,7000]}"#.utf8)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let metric = try decoder.decode(ZoopAPI.ProgressSummary.Metric.self, from: data)
        XCTAssertEqual(metric.weeks.count, 8); XCTAssertNil(metric.weeks[0]); XCTAssertNil(metric.change)
        XCTAssertEqual(metric.currentCount, 5)
    }
    func testChartOmitsOnlyAnEntirelyMissingPreviousPeriod() {
        let summary = Self.summary()
        let metric = ZoopAPI.ProgressSummary.Metric(key: "steps", current: 7000, previous: nil, change: nil, currentCount: 14, previousCount: 0, requiredCount: 21, weeks: [nil, nil, nil, nil, 6000, nil, 0, 8000])
        let chart = ProgressChartData(metric: metric, summary: summary)
        XCTAssertEqual(chart.weeks.map(\.id), [4, 5, 6, 7])
        XCTAssertNil(chart.weeks[1].value)
        XCTAssertEqual(chart.weeks[2].value, 0, "Recorded zero stays distinct from missing")
        XCTAssertEqual(chart.tickIDs, [4, 5, 6, 7])
        let full = ProgressChartData(metric: summary.metrics[0], summary: summary)
        XCTAssertEqual(full.weeks.count, 8)
        XCTAssertNil(full.weeks[0].value, "Keep gaps when the previous period has recordings")
        XCTAssertEqual(full.tickIDs, [0, 2, 4, 7])
    }
    func testChartWeekDatesUseLocalCalendarAcrossDST() throws {
        let summary = Self.summary("Europe/Berlin")
        let chart = ProgressChartData(metric: summary.metrics[0], summary: summary)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = summary.timeZone
        for week in chart.weeks { XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(week.start)), 0) }
        let before = try XCTUnwrap(chart.weeks[6].start), after = try XCTUnwrap(chart.weeks[7].start)
        XCTAssertEqual(after.timeIntervalSince(before), 7 * 86400 + 3600)
    }

}

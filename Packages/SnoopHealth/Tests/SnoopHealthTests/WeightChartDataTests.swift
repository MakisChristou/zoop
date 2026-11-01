import Foundation
import XCTest
@testable import SnoopHealth

final class WeightChartDataTests: XCTestCase {
    private func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func testThirtyDaysIsRollingAndIncludesToday() {
        let now = at("2026-11-01T20:00:00Z")
        let range = WeightChartData.Period.month.range(now: now, calendar: utc)
        XCTAssertEqual(range.start, at("2026-10-03T00:00:00Z"))
        XCTAssertEqual(range.end, at("2026-11-02T00:00:00Z"))
        XCTAssertEqual(utc.dateComponents([.day], from: range.start, to: range.end).day, 30)
    }
    func testWeekUsesLocalDaysAcrossDaylightSaving() {
        var cal = utc; cal.timeZone = TimeZone(identifier: "America/New_York")!
        let range = WeightChartData.Period.week.range(now: at("2025-03-09T20:00:00Z"), calendar: cal)
        XCTAssertEqual(range.start, at("2025-03-03T05:00:00Z"))
        XCTAssertEqual(range.end, at("2025-03-10T04:00:00Z"))
        XCTAssertEqual(cal.dateComponents([.day], from: range.start, to: range.end).day, 7)
        XCTAssertEqual(range.duration, 7 * 86400 - 3600)
    }
    func testEachRangeContainsOnlyItsActualMeasurements() {
        let now = at("2026-11-01T20:00:00Z")
        let rows = [
            WeightReading(id: "before", measuredAt: at("2026-10-02T23:59:59Z"), kg: 150),
            WeightReading(id: "early", measuredAt: at("2026-10-04T08:00:00Z"), kg: 90),
            WeightReading(id: "week", measuredAt: at("2026-10-27T08:00:00Z"), kg: 80),
            WeightReading(id: "today", measuredAt: at("2026-11-01T08:00:00Z"), kg: 82),
            WeightReading(id: "future", measuredAt: at("2026-11-02T00:00:00Z"), kg: 200)
        ]
        let month = WeightChartData(rows, range: WeightChartData.Period.month.range(now: now, calendar: utc), now: now, calendar: utc)
        let week = WeightChartData(rows, range: WeightChartData.Period.week.range(now: now, calendar: utc), now: now, calendar: utc)
        XCTAssertEqual(month.points.map(\.kg), [90, 80, 82])
        XCTAssertEqual(week.points.map(\.kg), [80, 82])
        XCTAssertEqual(month.points.map(\.segment), [0, 1, 1])
    }
    func testSourcePreferenceDuplicatesAndRemovalsPreserveActualWeights() {
        let date = at("2026-11-01T08:00:00Z"), now = at("2026-11-01T20:00:00Z")
        let external = WeightReading(id: "health:a", measuredAt: date, kg: 80, source: "health")
        let rows = [external, external,
            WeightReading(id: "health:b", measuredAt: date.addingTimeInterval(60), kg: 82, source: "health"),
            WeightReading(id: "own", measuredAt: date, kg: 100),
            WeightReading(id: "old", measuredAt: date, kg: 200, source: "health", version: 1),
            WeightReading(id: "old", measuredAt: date, kg: 200, source: "health", version: 2, removed: true),
            WeightReading(id: "past", measuredAt: at("2026-10-31T08:00:00Z"), kg: 78)
        ]
        let chart = WeightChartData(rows, range: WeightChartData.Period.week.range(now: now, calendar: utc), now: now, calendar: utc)
        XCTAssertEqual(chart.points.map(\.kg), [78, 80, 82])
    }
    func testLatestMatchesTodayWhenMeasurementsHaveTheSameTimestamp() {
        let date = at("2026-11-01T08:00:00Z"), now = at("2026-11-01T20:00:00Z")
        let rows = [
            WeightReading(id: "health:b", measuredAt: date, kg: 82, source: "health"),
            WeightReading(id: "health:a", measuredAt: date, kg: 80, source: "health")
        ]
        let chart = WeightChartData(rows, range: WeightChartData.Period.week.range(now: now, calendar: utc), now: now, calendar: utc)
        XCTAssertEqual(chart.points.last?.reading, WeightReading.preferred(rows, on: date, calendar: utc))
        XCTAssertEqual(chart.points.count, 2)
    }
    func testNinetyDaysIncludesLeapDayAndEmptyRangeHasNoInventedStatistics() {
        let now = at("2024-03-01T12:00:00Z")
        let range = WeightChartData.Period.quarter.range(now: now, calendar: utc)
        XCTAssertEqual(range.start, at("2023-12-03T00:00:00Z"))
        XCTAssertEqual(range.end, at("2024-03-02T00:00:00Z"))
        let chart = WeightChartData([], range: range, now: now, calendar: utc)
        XCTAssertTrue(chart.points.isEmpty)
    }
}

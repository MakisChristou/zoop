import Foundation
import XCTest
@testable import ZoopHealth

final class WeightChartWindowTests: XCTestCase {
    private func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var window: WeightChartWindow {
        WeightChartWindow(first: at("2026-01-01T08:00:00Z"), last: at("2026-11-01T08:00:00Z"), now: at("2026-11-01T20:00:00Z"), calendar: utc)
    }
    func testPagingHasNoSkippedOrRepeatedDatesAndCannotEnterFuture() {
        for days in [7, 30, 90] {
            let current = window.range(position: window.latestStart(days: days), days: days)
            let previous = window.range(position: window.latestStart(days: days) - Double(days), days: days)
            XCTAssertEqual(previous.end, current.start)
            XCTAssertEqual(utc.dateComponents([.day], from: previous.start, to: previous.end).day, days)
            XCTAssertEqual(window.range(position: 10000, days: days), current)
            XCTAssertEqual(current.end, at("2026-11-02T00:00:00Z"))
            XCTAssertEqual(window.range(position: -10000, days: days).start, at("2026-01-01T00:00:00Z"))
        }
    }
    func testChangingRangeKeepsTheBrowsedEndDate() {
        let older = window.range(position: window.latestStart(days: 30) - 30, days: 30)
        let week = window.range(position: window.position(endingAt: older.end, days: 7), days: 7)
        XCTAssertEqual(week.end, older.end)
        XCTAssertEqual(week.start, at("2026-09-26T00:00:00Z"))
    }
    func testShortAndSingleReadingHistoriesKeepWholeWindows() {
        let w = WeightChartWindow(first: at("2026-11-01T08:00:00Z"), last: at("2026-11-01T08:00:00Z"), now: at("2026-11-01T20:00:00Z"), calendar: utc)
        XCTAssertEqual(w.range(position: -1000, days: 30).start, at("2026-10-03T00:00:00Z"))
        XCTAssertEqual(w.clamp(1000, days: 30), w.clamp(-1000, days: 30))
        XCTAssertEqual(w.domain(days: nil), 0...1)
    }
    func testAllEndsAtLastReadingAndRestoringAfterRefreshKeepsDate() {
        let w = WeightChartWindow(first: at("2020-01-01T08:00:00Z"), last: at("2026-10-01T08:00:00Z"), now: at("2026-11-01T20:00:00Z"), calendar: utc)
        XCTAssertEqual(w.range(position: 9999, days: nil).end, at("2026-10-02T00:00:00Z"))
        let old = window.range(position: 100, days: 30)
        XCTAssertEqual(w.range(position: w.position(endingAt: old.end, days: 30), days: 30), old)
    }
    func testDayCoordinatesAndPagingAcrossBothDaylightSavingChanges() {
        var cal = utc; cal.timeZone = TimeZone(identifier: "America/New_York")!
        for (day, end, now, duration) in [
            ("2025-03-09T05:00:00Z", "2025-03-10T04:00:00Z", "2025-03-09T20:00:00Z", 23.0),
            ("2025-11-02T04:00:00Z", "2025-11-03T05:00:00Z", "2025-11-02T20:00:00Z", 25.0)
        ] {
            let w = WeightChartWindow(first: at("2025-01-01T08:00:00Z"), last: at(now), now: at(now), calendar: cal)
            let start = at(day)
            XCTAssertEqual(w.coordinate(at(end)) - w.coordinate(start), 1, accuracy: 0.00001)
            XCTAssertEqual(w.coordinate(start.addingTimeInterval(duration * 1800)) - w.coordinate(start), 0.5, accuracy: 0.00001)
            let range = w.range(position: w.latestStart(days: 7), days: 7)
            XCTAssertEqual(range.end, at(end))
            XCTAssertEqual(cal.dateComponents([.day], from: range.start, to: range.end).day, 7)
            XCTAssertEqual(range.duration, (6 * 24 + duration) * 3600)
        }
    }
}

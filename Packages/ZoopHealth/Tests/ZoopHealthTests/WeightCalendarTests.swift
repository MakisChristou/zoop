import Foundation
import XCTest
@testable import ZoopHealth

final class WeightCalendarTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; c.firstWeekday = 2; return c }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testMonthPagingUsesCalendarMonthsIncludingLeapYear() {
        let now = date("2024-03-31T12:00:00Z"), first = date("2023-01-01T00:00:00Z")
        let march = WeightCalendarPeriod.month.range(containing: now, first: first, last: now, calendar: calendar)
        let feb = WeightCalendarPeriod.month.moved(march, by: -1, first: first, now: now, calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: march.start), 1)
        XCTAssertEqual(calendar.dateComponents([.day], from: feb.start, to: feb.end).day, 29)
        XCTAssertEqual(WeightCalendarPeriod.month.moved(feb, by: 1, first: first, now: now, calendar: calendar), march)
        XCTAssertNil(WeightCalendarPeriod.month.moved(march, by: 1, first: first, now: now, calendar: calendar))
    }
    func testWeekAcrossDSTKeepsCalendarDatesAndRespectsLocale() {
        let now = date("2026-10-25T12:00:00Z"), first = date("2026-10-01T00:00:00Z")
        let week = WeightCalendarPeriod.week.range(containing: now, first: first, last: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: week.start), 2)
        XCTAssertEqual(calendar.dateComponents([.day], from: week.start, to: week.end).day, 7)
        XCTAssertEqual(week.duration, 7 * 86400 + 3600)
        var sunday = calendar; sunday.firstWeekday = 1
        XCTAssertNotEqual(WeightCalendarPeriod.week.range(containing: now, first: first, last: now, calendar: sunday), week)
    }
    func testThreeMonthsAndHistoryBoundaries() {
        let now = date("2026-11-03T12:00:00Z"), first = date("2026-08-20T12:00:00Z")
        let range = WeightCalendarPeriod.threeMonths.range(containing: now, first: first, last: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: range.start), 9)
        XCTAssertEqual(calendar.component(.month, from: range.end), 12)
        let older = WeightCalendarPeriod.threeMonths.moved(range, by: -1, first: first, now: now, calendar: calendar)!
        XCTAssertEqual(calendar.component(.month, from: older.start), 6)
        XCTAssertNil(WeightCalendarPeriod.threeMonths.moved(older, by: -1, first: first, now: now, calendar: calendar))
        XCTAssertNil(WeightCalendarPeriod.all.moved(range, by: -1, first: first, now: now, calendar: calendar))
    }
    func testCheckInCountsDatesNotReadingsAndHonoursHealthAndMissingDays() {
        let now = date("2026-11-03T12:00:00Z")
        let rows = [WeightReading(id: "local", measuredAt: now, kg: 70), WeightReading(id: "external", measuredAt: now.addingTimeInterval(-100), kg: 71, source: "health", sourceName: "Scale"), WeightReading(id: "yesterday", measuredAt: now.addingTimeInterval(-86400), kg: 72), WeightReading(id: "future", measuredAt: now.addingTimeInterval(86400), kg: 70), WeightReading(id: "removed", measuredAt: now.addingTimeInterval(-2*86400), kg: 70, removed: true)]
        let summary = WeightCheckInSummary(rows, now: now, calendar: calendar)
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.today?.id, "external")
        XCTAssertEqual(summary.latest?.kg, 71)
        XCTAssertEqual(summary.days.filter(\.isToday).count, 1)
        XCTAssertEqual(summary.days.filter(\.recorded).count, 2)
    }
    func testOldJournalDecodesWithoutCachedWake() throws {
        var journal = HealthJournal(); journal.lastConfirmedWake = date("2026-11-03T08:00:00Z")
        let data = try JSONEncoder().encode(journal)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); json.removeValue(forKey: "lastConfirmedWake")
        XCTAssertNil(try JSONDecoder().decode(HealthJournal.self, from: JSONSerialization.data(withJSONObject: json)).lastConfirmedWake)
    }
}

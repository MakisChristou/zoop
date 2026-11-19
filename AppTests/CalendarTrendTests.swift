import XCTest
import ZoopData
@testable import Zoop

final class CalendarTrendTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Europe/Berlin")!; result.firstWeekday = 2
        return result
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testCalendarPagesAcrossDSTLeapYearAndYearBoundary() {
        let week = TrendRange.week.interval(containing: date("2026-03-29T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(week.duration, 167 * 3600)
        let following = TrendRange.week.moved(week, by: 1, calendar: calendar)
        XCTAssertEqual(week.end, following.start)
        XCTAssertEqual(TrendRange.week.moved(following, by: -1, calendar: calendar), week)
        let leapMonth = TrendRange.month.interval(containing: date("2024-02-15T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: leapMonth.start, to: leapMonth.end).day, 29)
        let year = TrendRange.all.interval(containing: date("2026-12-31T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(calendar.component(.year, from: TrendRange.all.moved(year, by: 1, calendar: calendar).start), 2027)
        let quarter = TrendRange.quarter.interval(containing: date("2026-11-04T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: quarter.start), 10)
        XCTAssertEqual(calendar.component(.month, from: quarter.end), 1)
    }
    func testSparsePagesKeepCalendarBoundsAndExcludeNextMonth() {
        let now = date("2026-11-04T12:00:00Z")
        let snapshot = TrendSnapshot(nights: [TrendStoreTests.night(day: "2026-10-31"), TrendStoreTests.night(day: "2026-11-01")], days: [], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.series(.sleep, range: .month).points.count, 1)
        let october = date("2026-10-15T12:00:00Z")
        XCTAssertEqual(snapshot.series(.sleep, range: .month, containing: october).points.count, 1)
        XCTAssertTrue(snapshot.series(.sleep, range: .month, containing: date("2026-09-01T12:00:00Z")).points.isEmpty)
        let page = TrendRange.month.interval(containing: october, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: page.start), 1)
        XCTAssertEqual(calendar.component(.day, from: page.end), 1)
    }
    func testWeekdayPatternRequiresTwoReadingsForEachWeekdayAndDoesNotDependOnSelectedWeek() {
        let now = date("2026-11-04T12:00:00Z")
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = calendar.timeZone
        let nights = (0..<14).map { TrendStoreTests.night(day: formatter.string(from: calendar.date(byAdding: .day, value: -$0, to: now)!)) }
        XCTAssertNil(TrendSnapshot(nights: Array(nights.prefix(11)), days: [], now: now, calendar: calendar).weekdayPattern(.sleep))
        let snapshot = TrendSnapshot(nights: nights, days: [], now: now, calendar: calendar)
        XCTAssertNotNil(snapshot.weekdayPattern(.sleep))
        XCTAssertLessThan(snapshot.series(.sleep, range: .week).points.count, 14)
    }
    func testSleepReadoutsUseMinutes() {
        XCTAssertEqual(TrendMetric.sleep.formatted(494.0 / 60), "8h 14m")
        XCTAssertEqual(TrendMetric.sleep.formatted(59.0 / 60), "0h 59m")
    }
}

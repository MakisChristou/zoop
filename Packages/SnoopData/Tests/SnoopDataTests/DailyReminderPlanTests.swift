import XCTest
@testable import SnoopData

final class DailyReminderPlanTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }
    func testCompletionSkipsTodayAndKeepsTomorrow() {
        let entries = DailyReminderPlan.entries(scope: "test", kind: "weight", minute: 540, completedDays: ["2026-11-05"], attempted: [:], now: date("2026-11-05T06:00:00Z"), calendar: calendar)
        XCTAssertEqual(entries.count, 27); XCTAssertEqual(entries.first?.day, "2026-11-06")
    }
    func testNoLateCatchUpAndNoDuplicateAfterTimeChange() {
        let now = date("2026-11-05T10:00:00Z")
        let old = DailyReminderPlan.entries(scope: "test", kind: "weight", minute: 540, completedDays: [], attempted: [:], now: now, calendar: calendar)
        XCTAssertEqual(old.first?.day, "2026-11-06")
        let id = "snoop.daily.test.weight.2026-11-05"
        let changed = DailyReminderPlan.entries(scope: "test", kind: "weight", minute: 900, completedDays: [], attempted: [id: date("2026-11-05T08:00:00Z")], now: now, calendar: calendar)
        XCTAssertEqual(changed.first?.day, "2026-11-06")
    }
    func testCalendarTimesSurviveDSTAndNonexistentTime() {
        for start in ["2026-03-28T00:00:00Z", "2026-10-24T00:00:00Z"] {
            let entries = DailyReminderPlan.entries(scope: "test", kind: "ecg", minute: 1200, completedDays: [], attempted: [:], now: date(start), calendar: calendar)
            XCTAssertEqual(entries.count, 28); XCTAssertEqual(Set(entries.map(\.id)).count, 28)
            XCTAssertTrue(entries.allSatisfy { calendar.component(.hour, from: $0.date) == 20 })
        }
        let gap = DailyReminderPlan.entries(scope: "test", kind: "weight", minute: 150, completedDays: [], attempted: [:], now: date("2026-03-29T00:00:00Z"), calendar: calendar)
        XCTAssertEqual(gap.first?.day, "2026-03-29"); XCTAssertEqual(calendar.component(.hour, from: gap[0].date), 3)
    }
    func testInvalidTimeAndMissingScopeDoNotSchedule() {
        XCTAssertTrue(DailyReminderPlan.entries(scope: "", kind: "weight", minute: 540, completedDays: [], attempted: [:], now: Date()).isEmpty)
        XCTAssertTrue(DailyReminderPlan.entries(scope: "test", kind: "weight", minute: 1440, completedDays: [], attempted: [:], now: Date()).isEmpty)
    }
}

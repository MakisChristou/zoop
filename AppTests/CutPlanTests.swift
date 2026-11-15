import XCTest
import SnoopHealth
import UserNotifications
@testable import Snoop

@MainActor final class CutPlanTests: XCTestCase {
    func testProjectionUsesLocalCalendarDaysAcrossDSTAndUnitsStayKilograms() throws {
        let calendar = CutPlan.calendar(timezone: "Europe/Berlin")
        let start = try XCTUnwrap(CutPlan.date("2026-03-23", calendar: calendar)), end = try XCTUnwrap(CutPlan.date("2026-03-30", calendar: calendar))
        XCTAssertEqual(CutPlan.target(starting: 70, rate: 0.3, start: start, finish: end, calendar: calendar), 69.7)
        XCTAssertEqual(CutPlan.key(end, calendar: calendar), "2026-03-30")
        XCTAssertNil(CutPlan.target(starting: nil, rate: 0.3, start: start, finish: end, calendar: calendar))
        XCTAssertNil(CutPlan.target(starting: 70, rate: 0.3, start: end, finish: start, calendar: calendar))
    }
    func testPreviewBaselineUsesHealthPriorityAndRejectsStaleFutureAndRemoved() throws {
        let calendar = CutPlan.calendar(timezone: "UTC")
        let start = try XCTUnwrap(CutPlan.date("2026-11-16", calendar: calendar))
        let rows = [WeightReading(id: "health:a", measuredAt: start, kg: 70, source: "health"), WeightReading(measuredAt: start, kg: 80), WeightReading(measuredAt: start.addingTimeInterval(-86400), kg: 72), WeightReading(measuredAt: start.addingTimeInterval(86400), kg: 90), WeightReading(measuredAt: start, kg: 100, removed: true)]
        XCTAssertEqual(CutPlan.baseline(rows, start: start, calendar: calendar, now: start), 71)
    }
    func testClearingFinishDateEncodesExplicitNullForCompatibility() throws {
        let input = SnoopAPI.WeightGoalInput(revision: 1, active: true, timezone: "UTC", weeklyLossKg: 0.3, reminderEnabled: false, reminderWeekday: 1, reminderMinute: 1200)
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(input)) as? [String: Any])
        XCTAssertTrue(json["finish_date"] is NSNull)
    }
    func testDatedRemindersStopAtFinishWithoutRequiringAppToWake() async throws {
        let calendar = CutPlan.calendar(timezone: "UTC")
        var now = try XCTUnwrap(CutPlan.date("2026-11-16", calendar: calendar))
        var requests: [String: UNNotificationRequest] = [:]
        let center = ReminderNotificationClient(authorization: { .authorized }, pending: { Array(requests.values) }, delivered: { [] }, add: { requests[$0.identifier] = $0 }, removePending: { ids in ids.forEach { requests.removeValue(forKey: $0) } }, removeDelivered: { _ in })
        let reminder = WeeklyWeightReminder(center: center, now: { now })
        var goal = SnoopAPI.WeightGoal(revision: 1, active: true, startedAt: now, paceStartedAt: now, timezone: "UTC", weeklyLossKg: 0.3, reminderEnabled: true, reminderWeekday: 1, reminderMinute: 1200, updatedAt: now)
        goal.finishDate = "2026-11-29"
        reminder.update(goal: goal, scope: "test"); await reminder.settled()
        XCTAssertEqual(requests.count, 2)
        for request in requests.values {
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            XCTAssertFalse(trigger.repeats); XCTAssertTrue([22, 29].contains(trigger.dateComponents.day!))
        }
        now = try XCTUnwrap(CutPlan.date("2026-11-30", calendar: calendar))
        reminder.update(goal: goal, scope: "test"); await reminder.settled(); XCTAssertTrue(requests.isEmpty)
    }
}

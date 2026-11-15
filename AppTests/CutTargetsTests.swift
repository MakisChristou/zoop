import XCTest
@testable import Snoop

@MainActor final class CutTargetsTests: XCTestCase {
    let calendar = CutPlan.calendar(timezone: "UTC")
    private func day(_ key: String) -> Date { CutPlan.date(key, calendar: calendar)! }
    private func goal(timezone: String = "UTC") -> SnoopAPI.WeightGoal {
        var goal = SnoopAPI.WeightGoal(revision: 1, active: true, startedAt: day("2026-11-16"), paceStartedAt: day("2026-11-16"), timezone: timezone, weeklyLossKg: 0.3, reminderEnabled: false, reminderWeekday: 1, reminderMinute: 1200, updatedAt: day("2026-11-16"))
        goal.dailyStepsGoal = 8000; goal.finishDate = "2026-12-13"; return goal
    }
    func testStepsOnlyApplyToCurrentDayWithinActiveCut() {
        var g = goal(); let today = day("2026-11-20")
        XCTAssertEqual(CutTargets.steps(goal: g, day: today, now: today, calendar: calendar), 8000)
        XCTAssertNil(CutTargets.steps(goal: g, day: day("2026-11-19"), now: today, calendar: calendar))
        XCTAssertNil(CutTargets.steps(goal: g, day: day("2026-11-15"), now: day("2026-11-15"), calendar: calendar))
        XCTAssertEqual(CutTargets.steps(goal: g, day: day("2026-12-13"), now: day("2026-12-13"), calendar: calendar), 8000)
        XCTAssertNil(CutTargets.steps(goal: g, day: day("2026-12-14"), now: day("2026-12-14"), calendar: calendar))
        g.active = false; XCTAssertNil(CutTargets.steps(goal: g, day: today, now: today, calendar: calendar))
        g.active = true; g.dailyStepsGoal = nil; XCTAssertNil(CutTargets.steps(goal: g, day: today, now: today, calendar: calendar))
    }
    func testTargetLineClipsToCutWithoutRewritingEarlierPeriods() {
        let target = WeightChartTarget(kg: 60.9, period: .init(start: day("2026-11-16"), end: day("2026-12-14")))
        XCTAssertNil(target.segment(in: .init(start: day("2026-10-01"), end: day("2026-11-01"))))
        XCTAssertEqual(target.segment(in: .init(start: day("2026-11-01"), end: day("2026-12-01"))), .init(start: day("2026-11-16"), end: day("2026-12-01")))
        XCTAssertNil(target.segment(in: .init(start: day("2026-12-14"), end: day("2027-01-01"))))
    }
    func testGoalTimezoneControlsFinishBoundary() {
        let g = goal(timezone: "Asia/Nicosia")
        let now = day("2026-12-13").addingTimeInterval(23 * 3600)
        XCTAssertNil(CutTargets.steps(goal: g, day: now, now: now, calendar: calendar))
    }
    func testClearingStepGoalIsExplicitNull() throws {
        let input = SnoopAPI.WeightGoalInput(revision: 1, active: true, timezone: "UTC", weeklyLossKg: 0.3, reminderEnabled: false, reminderWeekday: 1, reminderMinute: 1200)
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(input)) as? [String:Any])
        XCTAssertTrue(json["daily_steps_goal"] is NSNull)
    }
}

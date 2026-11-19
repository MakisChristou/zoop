import Foundation

enum CutTargets {
    static func weight(goal: ZoopAPI.WeightGoal?, summary: ZoopAPI.WeeklyWeightSummary?) -> WeightChartTarget? {
        guard let goal, goal.active, let kg = summary?.progress?.targetWeightKg, kg.isFinite, (20...400).contains(kg) else { return nil }
        let calendar = CutPlan.calendar(timezone: goal.timezone)
        guard let finish = CutPlan.date(goal.finishDate, calendar: calendar), let end = calendar.date(byAdding: .day, value: 1, to: finish) else { return nil }
        guard end > calendar.startOfDay(for: goal.startedAt) else { return nil }
        return .init(kg: kg, period: DateInterval(start: calendar.startOfDay(for: goal.startedAt), end: end))
    }
    /// Current-day goal only; changing a target never rewrites past-day comparisons.
    static func steps(goal: ZoopAPI.WeightGoal?, day: Date, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard calendar.isDate(day, inSameDayAs: now), let goal, goal.active, let steps = goal.dailyStepsGoal, (1...100_000).contains(steps) else { return nil }
        let goalCalendar = CutPlan.calendar(timezone: goal.timezone)
        let today = goalCalendar.startOfDay(for: now)
        guard today >= goalCalendar.startOfDay(for: goal.startedAt) else { return nil }
        if let finish = CutPlan.date(goal.finishDate, calendar: goalCalendar), today > finish { return nil }
        return steps
    }
}

import Foundation

/// Presentation only. Server medians and eligibility remain authoritative.
struct CutProgressData {
    struct TimeProgress: Equatable {
        let elapsed: Int
        let total: Int
        var remaining: Int { max(0, total - elapsed) }
        var fraction: Double { Double(elapsed) / Double(total) }
    }
    struct Point: Identifiable {
        let date: Date
        let kg: Double
        let segment: Int
        let weekID: String
        var id: String { weekID }
    }
    let goal: SnoopAPI.WeightGoal
    let summary: SnoopAPI.WeeklyWeightSummary
    let calendar: Calendar
    let start: Date
    let finish: Date?
    let today: Date
    let weeks: [SnoopAPI.WeightWeek]

    init(goal: SnoopAPI.WeightGoal, summary: SnoopAPI.WeeklyWeightSummary, now: Date = Date()) {
        self.goal = goal; self.summary = summary
        let calendar = CutPlan.calendar(timezone: goal.timezone)
        self.calendar = calendar
        start = calendar.startOfDay(for: goal.startedAt)
        let finish = CutPlan.date(goal.finishDate, calendar: calendar)
        self.finish = finish
        let today = calendar.startOfDay(for: now)
        self.today = today
        let pace = calendar.startOfDay(for: goal.paceStartedAt)
        var available = summary.weeks.filter {
            guard let end = CutPlan.date($0.end, calendar: calendar), let begin = CutPlan.date($0.start, calendar: calendar) else { return false }
            return end >= pace && begin <= today && (finish == nil || begin <= finish!)
        }
        if !available.contains(where: { $0.start == summary.start }) {
            available.append(.init(start: summary.start, end: summary.end, medianKg: summary.medianKg, count: summary.count, eligible: false))
        }
        weeks = available.sorted { $0.start < $1.start }
    }
    var time: TimeProgress? {
        guard let finish else { return nil }
        let total = days(start, finish)
        guard total > 0 else { return nil }
        return .init(elapsed: min(total, max(0, days(start, today))), total: total)
    }
    var completed: Bool { finish.map { today > $0 } ?? false }
    var plannedLoss: Double? {
        guard let initial = summary.progress?.startingWeightKg, let target = summary.progress?.targetWeightKg,
              initial.isFinite, target.isFinite, initial > target else { return nil }
        return initial - target
    }
    var weightFraction: Double? {
        guard let loss = summary.progress?.totalLostKg, loss.isFinite, let plannedLoss else { return nil }
        return min(1, max(0, loss / plannedLoss))
    }
    func days(_ from: Date, _ to: Date) -> Int { calendar.dateComponents([.day], from: from, to: to).day ?? 0 }
    func date(_ key: String) -> Date { CutPlan.date(key, calendar: calendar) ?? start }
    func number(_ week: SnoopAPI.WeightWeek) -> Int {
        // Monday-based reporting weeks, including a partial opening week.
        // Counting elapsed seven-day blocks gives two "Week 1" pages for midweek starts.
        let offset = (calendar.component(.weekday, from: start) + 5) % 7
        let firstMonday = calendar.date(byAdding: .day, value: -offset, to: start)!
        return max(1, days(firstMonday, date(week.start)) / 7 + 1)
    }
    func change(_ week: SnoopAPI.WeightWeek) -> Double? {
        if week.start == summary.start { return summary.changeKg }
        guard let index = weeks.firstIndex(where: { $0.id == week.id }), index > 0 else { return nil }
        let previous = weeks[index - 1]
        guard week.eligible, previous.eligible, days(date(previous.start), date(week.start)) == 7,
              let before = previous.medianKg, let after = week.medianKg else { return nil }
        return after - before
    }
    var points: [Point] {
        var segment = 0
        return weeks.compactMap { week in
            // Incomplete medians are inspectable dots, never joined to imply a reliable trend.
            guard let kg = week.medianKg, kg.isFinite else { segment += 1; return nil }
            if !week.eligible { segment += 1 }
            let point = Point(date: min(date(week.end), finish ?? today, today), kg: kg, segment: segment, weekID: week.id)
            if !week.eligible { segment += 1 }
            return point
        }
    }
    /// A changed pace must not rewrite the target path of earlier weeks.
    var targetPath: [(date: Date, kg: Double)] {
        guard calendar.isDate(goal.startedAt, inSameDayAs: goal.paceStartedAt),
              let finish, finish > start, let initial = summary.progress?.startingWeightKg,
              let target = summary.progress?.targetWeightKg, initial.isFinite, target.isFinite else { return [] }
        return [(start, initial), (finish, target)]
    }
    var domain: ClosedRange<Date> {
        let last = max(finish ?? today, points.last?.date ?? today)
        return start...max(last, calendar.date(byAdding: .day, value: 7, to: start)!)
    }
}

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
        let weekID: String
        var id: Date { date }
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
        var seen = Set<Date>()
        return (summary.progress?.weighIns ?? []).compactMap { reading in
            guard let day = CutPlan.date(reading.day, calendar: calendar),
                  day >= start, day <= min(finish ?? today, today),
                  reading.kg.isFinite, (20...400).contains(reading.kg),
                  seen.insert(day).inserted else { return nil }
            let offset = (calendar.component(.weekday, from: day) + 5) % 7
            let monday = calendar.date(byAdding: .day, value: -offset, to: day)!
            return Point(date: day, kg: reading.kg,
                         weekID: CutPlan.key(monday, calendar: calendar))
        }.sorted { $0.date < $1.date }
    }

    /// A changed pace must not rewrite the target path of earlier weeks.
    var targetPath: [(date: Date, kg: Double)] {
        guard calendar.isDate(goal.startedAt, inSameDayAs: goal.paceStartedAt),
              let finish, finish > start, let initial = summary.progress?.startingWeightKg,
              let target = summary.progress?.targetWeightKg, initial.isFinite, target.isFinite else { return [] }
        return [(start, initial), (finish, target)]
    }
    /// The selected calendar week's elapsed portion, clipped to the cut.
    func window(for week: SnoopAPI.WeightWeek) -> ClosedRange<Date> {
        let lower = max(start, date(week.start))
        let upper = max(lower, min(date(week.end), today, finish ?? today))
        return lower...upper
    }
    func points(in week: SnoopAPI.WeightWeek) -> [Point] {
        let bounds = window(for: week)
        return points.filter { bounds.contains($0.date) }
    }
    func domain(for week: SnoopAPI.WeightWeek) -> ClosedRange<Date> {
        let bounds = window(for: week)
        // Half-day shoulders keep a single day centered and edge dots fully visible.
        let lower = calendar.date(byAdding: .hour, value: -12, to: bounds.lowerBound)!
        let upper = calendar.date(byAdding: .hour, value: 12, to: bounds.upperBound)!
        return lower...upper
    }
    func targetPath(in week: SnoopAPI.WeightWeek) -> [(date: Date, kg: Double)] {
        guard let first = targetPath.first, let last = targetPath.last else { return [] }
        let bounds = window(for: week)
        let total = Double(days(first.date, last.date))
        guard total > 0 else { return [] }
        return [bounds.lowerBound, bounds.upperBound].map { date in
            (date, first.kg + (last.kg - first.kg) * Double(days(first.date, date)) / total)
        }
    }
}

import Foundation

/// Calendar pages for recorded measurements. Ends are exclusive.
public enum WeightCalendarPeriod: String, CaseIterable, Identifiable, Sendable {
    case week = "Week", month = "Month", threeMonths = "3 months", all = "All"
    public var id: Self { self }
    public func range(containing date: Date, first: Date, last: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .week: return calendar.dateInterval(of: .weekOfYear, for: date)!
        case .month: return calendar.dateInterval(of: .month, for: date)!
        case .threeMonths:
            let month = calendar.dateInterval(of: .month, for: date)!
            return DateInterval(start: calendar.date(byAdding: .month, value: -2, to: month.start)!, end: month.end)
        case .all:
            let start = calendar.startOfDay(for: min(first, last))
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))!)
        }
    }
    public func moved(_ range: DateInterval, by direction: Int, first: Date, now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard self != .all, direction != 0 else { return nil }
        let component: Calendar.Component = self == .week ? .weekOfYear : .month
        let amount = direction * (self == .threeMonths ? 3 : 1)
        let anchor = self == .week ? range.start : calendar.date(byAdding: .day, value: -1, to: range.end)!
        guard let date = calendar.date(byAdding: component, value: amount, to: anchor) else { return nil }
        let proposed = self.range(containing: date, first: first, last: now, calendar: calendar)
        let latest = self.range(containing: now, first: first, last: now, calendar: calendar)
        guard proposed.end > calendar.startOfDay(for: first), proposed.start <= latest.start else { return nil }
        return proposed
    }
}

import Foundation

/// Calendar pages, with exclusive upper bounds. Navigation uses calendar arithmetic.
enum TrendRange: String, CaseIterable, Identifiable, Sendable {
    case week = "Week", month = "Month", quarter = "3 months", all = "Year"
    var id: String { rawValue }
    static let historyLimit = 365
    var days: Int { switch self { case .week: 7; case .month: 30; case .quarter: 90; case .all: Self.historyLimit } }

    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        switch self {
        case .week: return calendar.dateInterval(of: .weekOfYear, for: date)!
        case .month: return calendar.dateInterval(of: .month, for: date)!
        case .all: return calendar.dateInterval(of: .year, for: date)!
        case .quarter:
            let month = calendar.dateInterval(of: .month, for: date)!.start
            let offset = (calendar.component(.month, from: month) - 1) % 3
            let start = calendar.date(byAdding: .month, value: -offset, to: month)!
            return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 3, to: start)!)
        }
    }
    func moved(_ interval: DateInterval, by direction: Int, calendar: Calendar) -> DateInterval {
        let component: Calendar.Component = self == .week ? .weekOfYear : self == .all ? .year : .month
        let date = calendar.date(byAdding: component, value: direction * (self == .quarter ? 3 : 1), to: interval.start)!
        return self.interval(containing: date, calendar: calendar)
    }
    func title(_ interval: DateInterval, calendar: Calendar) -> String {
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        switch self {
        case .month: return interval.start.formatted(style.month(.wide).year())
        case .all: return interval.start.formatted(style.year())
        case .week, .quarter:
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end)!
            return interval.start.formatted(style.day().month(.abbreviated)) + " – " + last.formatted(style.day().month(.abbreviated).year())
        }
    }
}

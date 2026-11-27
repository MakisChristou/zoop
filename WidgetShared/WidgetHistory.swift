import Foundation

enum WidgetHistory {
    static let weeks = 20
    static let recoveryDays = 30

    static func calendarDays(ending end: Date, count: Int, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: end)
        return (1 - count...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// Monday-first columns, including the unfilled part of the current week.
    static func heatmapDays(through date: Date, calendar: Calendar) -> [Date] {
        let weekday = calendar.component(.weekday, from: date)
        let untilSunday = (8 - weekday) % 7
        let sunday = calendar.date(byAdding: .day, value: untilSunday, to: date)!
        return calendarDays(ending: sunday, count: weeks * 7, calendar: calendar)
    }

    static func loadLevel(_ load: Double) -> Int {
        Int(ceil(min(21, max(0, load)) / 4.2))
    }
}

extension WidgetSnapshot {
    struct ActivityHistory: Codable, Equatable {
        let refreshed: Date
        let zone: String
        var loads: [Date: Double]

        func isFresh(on day: Date, calendar: Calendar) -> Bool {
            zone == calendar.timeZone.identifier && calendar.isDate(refreshed, inSameDayAs: day)
        }
    }
}

extension WidgetSnapshot {
    /// Trim empty margins, preserving one horizontal slot for each intervening calendar day.
    func recoverySpan(through date: Date, count: Int, calendar: Calendar = .current) -> [Recovery?] {
        let indexed = Dictionary(recovery.filter { $0.score != nil }.map { (calendar.startOfDay(for: $0.day), $0) },
                                 uniquingKeysWith: { _, newest in newest })
        let values = WidgetHistory.calendarDays(ending: date, count: count, calendar: calendar).map { indexed[$0] }
        guard let first = values.firstIndex(where: { $0 != nil }), let last = values.lastIndex(where: { $0 != nil }) else { return [] }
        return Array(values[first...last])
    }
}

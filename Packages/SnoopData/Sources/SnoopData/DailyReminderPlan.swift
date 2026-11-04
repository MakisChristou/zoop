import Foundation

/// Bounded, one-shot calendar reminders. Completion cancels today without cancelling
/// tomorrow. A due scheduling receipt prevents another attempt after a time change.
public enum DailyReminderPlan {
    public static let horizon = 28
    public struct Entry: Equatable, Sendable {
        public let id: String
        public let kind: String
        public let day: String
        public let date: Date
    }
    public static func entries(scope: String, kind: String, minute: Int, completedDays: Set<String>,
                               attempted: [String: Date], now: Date, calendar: Calendar = .current) -> [Entry] {
        guard !scope.isEmpty, (0..<1440).contains(minute) else { return [] }
        return (0..<horizon).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day,
                                           matchingPolicy: .nextTime, repeatedTimePolicy: .first),
                  calendar.isDate(date, inSameDayAs: day), date > now else { return nil }
            let key = DayKey.string(day, timeZone: calendar.timeZone)
            let id = "snoop.daily.\(scope).\(kind).\(key)"
            guard !completedDays.contains(key), attempted[id].map({ $0 > now }) ?? true else { return nil }
            return Entry(id: id, kind: kind, day: key, date: date)
        }
    }
}
